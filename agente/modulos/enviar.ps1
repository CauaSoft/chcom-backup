<#
================================================================================
  CH.Com Cofre - cifrar e enviar para a AWS

  DUAS COISAS QUE ESTA ETAPA RESOLVE E O DUPLICATI NAO RESOLVIA

  1. VAI DIRETO PARA O DEEP ARCHIVE, sem regra de ciclo de vida.

     A regra de ciclo de vida do S3 filtra por prefixo e por etiqueta - NAO
     por final de nome. Com o Duplicati, os indices ficavam no mesmo prefixo
     dos dados e congelavam junto: para recuperar um arquivo de 10 KB era
     preciso descongelar o repositorio inteiro.

     O rclone grava a classe no proprio envio:
         --s3-storage-class DEEP_ARCHIVE
     Cada arquivo nasce na classe certa. Nao ha indice compartilhado, nao ha
     nada para descongelar alem do que se quer.

  2. CADA COPIA E INDEPENDENTE.

     Nao ha deduplicacao entre execucoes. Uma copia de marco nao depende de
     nada da copia de fevereiro. Perder uma nao afeta as outras - o oposto de
     um repositorio deduplicado, onde um bloco perdido estraga versoes
     arbitrarias.

  A CRIPTOGRAFIA

  rclone crypt: AES-256 em modo CTR, com HMAC-SHA256, aplicado NESTE servidor
  antes de qualquer byte sair. A AWS recebe conteudo cifrado e nomes de
  arquivo cifrados. Nem a Amazon, nem quem tiver as credenciais da conta,
  consegue ler.

  O QUE ISSO EXIGE EM TROCA

  Sem a chave, o que esta na AWS e lixo irrecuperavel. A chave e o ativo mais
  importante do sistema inteiro, e por isso o instalador obriga a guardar em
  tres lugares - um deles fora do cartorio.
================================================================================
#>

function CaminhoDoRclone([string]$raiz) {
    $r = CaminhoDe $raiz 'rclone.exe'
    if (Test-Path $r) { return $r }
    try { return (Get-Command rclone.exe -ErrorAction Stop).Source } catch { }
    return $null
}

<#
    Envia uma pasta.

    O rclone e chamado com o arquivo de configuracao explicito. Sem isso ele
    procura em %APPDATA%, que muda conforme o usuario - e o Cofre roda como
    servico do sistema, com outro %APPDATA% que o do tecnico que instalou.
    Um caminho explicito elimina a classe inteira de "funciona quando eu rodo
    e falha no agendamento".
#>
function EnviarPasta {
    param(
        [Parameter(Mandatory)] [string]$Rclone,
        [Parameter(Mandatory)] [string]$Config,
        [Parameter(Mandatory)] [string]$Origem,
        [Parameter(Mandatory)] [string]$DestinoRemoto,   # ex: cofre:cartorio/host/vm/2026-08-25
        [string]$ClasseArmazenamento = 'DEEP_ARCHIVE',
        [int]$TransferenciasSimultaneas = 4,
        [scriptblock]$AoProgredir
    )

    $r = [PSCustomObject]@{
        Origem = $Origem; Destino = $DestinoRemoto; Sucesso = $false
        BytesEnviados = 0; Arquivos = 0; Duracao = [TimeSpan]::Zero
        Erro = $null; Saida = @()
    }
    $relogio = [Diagnostics.Stopwatch]::StartNew()

    try {
        <#
            O QUE ENCHE O LINK E O PARALELISMO, NAO A ESPERA.

            Medido num cartorio: 8 MB num fluxo unico deram 10,6 Mbps. Um
            fluxo so passa metade do tempo esperando o "recebi" atravessar o
            continente - e o link fica ocioso nesse tempo.

            --s3-upload-concurrency sobe PEDACOS DO MESMO ARQUIVO ao mesmo
            tempo. Para copia de VM, que e um arquivo unico de dezenas de GB,
            e o unico paralelismo que existe: --transfers nao ajuda quando ha
            um arquivo so.

            Os numeros saem da RAM da maquina. Ver AjusteDeTransferencia - a
            conta de memoria esta explicada la, e ela ja derrubaria um
            servidor de 4 GB se fosse fixa.
        #>
        $ajuste = AjusteDeTransferencia
        $argumentos = @(
            'copy', $Origem, $DestinoRemoto
            '--config', $Config
            '--s3-storage-class', $ClasseArmazenamento
            '--transfers', $ajuste.Arquivos
            '--s3-upload-concurrency', $ajuste.Pedacos
            '--s3-chunk-size', ("$($ajuste.PedacoMB)M")
            <#
                LER O ARQUIVO DUAS VEZES ANTES DE COMECAR A SUBIR.

                Por padrao o rclone calcula o MD5 do arquivo INTEIRO antes de
                enviar, para gravar junto do objeto. Numa VM exportada de 21 GB
                isso significa ler 21 GB do disco antes de o primeiro byte sair
                para a rede - com o link parado esse tempo todo.

                Desligar nao deixa o backup sem defesa: a criptografia do rclone
                autentica CADA BLOCO de 64 KB com Poly1305. Se um byte chegar
                trocado, a restauracao acusa - e acusa dizendo qual arquivo. O
                MD5 no metadado seria uma segunda conferencia da mesma coisa,
                paga com um passeio inteiro pelo disco.
            #>
            '--s3-disable-checksum'
            <#
                Sem esta linha o rclone faz um HeadBucket antes de cada envio.

                Sao dois problemas num: um ida e volta a toa por transferencia,
                e uma chamada NO NIVEL DO BUCKET - que a politica do cartorio
                nao concede de proposito, porque ela e restrita ao prefixo. O
                envio falharia por permissao sem ter nada de errado.
            #>
            '--s3-no-check-bucket'
            # Comparar o que ja existe la e barato e paralelo. Numa pasta de
            # banco com milhares de arquivos, e isto que decide o tempo.
            '--checkers', '16'
            '--stats', '5s'
            '--stats-one-line'
            # Link de cartorio cai. Retomar e regra, nao excecao.
            '--retries', '10'
            '--low-level-retries', '20'
            '--retries-sleep', '30s'
        )

        # INFO no log de arquivo: guarda o que aconteceu sem que uma linha de
        # sucesso vire erro na tela. Ver RodarRclone.
        $exec = RodarRclone -Rclone $Rclone -Argumentos $argumentos -Nivel 'INFO'
        $r.Saida = @($exec.Log)
        if ($exec.Codigo -ne 0) { throw $exec.Erro }

        $r.Sucesso = $true
        foreach ($f in @(Get-ChildItem $Origem -Recurse -File -ErrorAction SilentlyContinue)) {
            $r.Arquivos++
            $r.BytesEnviados += $f.Length
        }

    } catch {
        $r.Erro = $_.Exception.Message
    } finally {
        $relogio.Stop(); $r.Duracao = $relogio.Elapsed
    }
    return $r
}

<#
    Confere que o que subiu esta la, com o tamanho certo.

    Nao da para BAIXAR e comparar: em Deep Archive isso custa dinheiro e leva
    de 12 a 48 horas. O que da para fazer sem descongelar nada e listar - a
    listagem le os metadados, que continuam acessiveis.

    Isso prova que o objeto existe e tem o tamanho esperado. Nao prova o
    conteudo - o conteudo foi provado ANTES de subir, pela validacao local e
    pelo manifesto SHA-256, e o proprio S3 confere o MD5 de cada pedaco no
    envio. E o maximo que se pode afirmar honestamente sem gastar resgate.
#>
function ConferirEnvio {
    param(
        [Parameter(Mandatory)] [string]$Rclone,
        [Parameter(Mandatory)] [string]$Config,
        [Parameter(Mandatory)] [string]$DestinoRemoto,
        [Parameter(Mandatory)] [long]$BytesEsperados
    )

    $r = [PSCustomObject]@{ Confere = $false; BytesNoDestino = 0; Arquivos = 0; Erro = $null }

    try {
        $exec = RodarRclone -Rclone $Rclone -Argumentos @(
            'lsjson', $DestinoRemoto, '--config', $Config, '--recursive')
        if ($exec.Codigo -ne 0) { throw "nao consegui listar o destino: $($exec.Erro)" }

        # O JSON vem limpo porque o log foi para arquivo. Antes, uma linha de
        # log caindo no meio do stdout quebrava esta leitura.
        $itens = LerListaDoRclone $exec.Saida
        foreach ($i in $itens) {
            if ($i.IsDir) { continue }
            $r.Arquivos++
            $r.BytesNoDestino += [long]$i.Size
        }

        # A criptografia acrescenta cabecalho e blocos de autenticacao por
        # arquivo, entao o tamanho no destino e MAIOR que o de origem. Conferir
        # igualdade exata acusaria erro em todo envio correto; o que se confere
        # e que nao FALTA nada.
        $r.Confere = ($r.Arquivos -gt 0 -and $r.BytesNoDestino -ge $BytesEsperados)
        if (-not $r.Confere -and $r.Arquivos -gt 0) {
            $r.Erro = "o destino tem menos dados que a origem ($($r.BytesNoDestino) contra $BytesEsperados)"
        } elseif ($r.Arquivos -eq 0) {
            $r.Erro = 'o destino esta vazio'
        }

    } catch {
        $r.Erro = $_.Exception.Message
    }
    return $r
}

<#
================================================================================
    PUBLICAR O ESTADO NO BUCKET

    E o que substitui o painel-servidor.

    ANTES: cada cartorio fazia POST para um servidor web, que precisava de
    endereco publico, dominio, HTTPS, token e uma maquina ligada 24 horas.

    AGORA: o agente grava o proprio estado.json no bucket, ao lado do backup.
    O programa do gerente le todos os buckets e monta a tela. Nenhum servidor
    no meio, nada exposto na internet, nada para manter no ar.

    ONDE FICA

        backup-aws-ch/<CARTORIO>/<SERVIDOR>/_estado/estado.json

    Fora da estrutura de datas de proposito: e o estado ATUAL, sobrescrito a
    cada execucao. O historico vive nas pastas de data, que ja existem.

    O sublinhado no "_estado" nao e enfeite: faz a pasta aparecer no topo da
    listagem, separada das datas, em qualquer ordenacao alfabetica.

    O QUE VAI, E O QUE NAO VAI

    Vai o resumo: o que foi protegido, quando, quanto, e se deu certo.
    NAO vai chave, credencial, nem nome de arquivo do cliente. Quem le esse
    arquivo precisa saber SE o backup existe, nao o que tem dentro dele.
================================================================================
#>
function PublicarEstado {
    param(
        [Parameter(Mandatory)] [string]$Rclone,
        [Parameter(Mandatory)] [string]$Config,
        # O remote SEM cifra, e o bucket: ver o comentario grande abaixo.
        [string]$RemotoSemCifra = 'cofre-s3',
        [Parameter(Mandatory)] [string]$Bucket,
        [Parameter(Mandatory)] [string]$Cartorio,
        [Parameter(Mandatory)] [string]$Servidor,
        [Parameter(Mandatory)] [string]$ArquivoEstado
    )

    $r = [PSCustomObject]@{ Publicado = $false; Destino = $null; Erro = $null }

    if (-not (Test-Path $ArquivoEstado)) {
        $r.Erro = 'nao ha estado para publicar'
        return $r
    }

    # Uma pasta temporaria com o arquivo dentro: o rclone copy trabalha com
    # pastas, e copiar a pasta de dados inteira levaria junto a configuracao
    # e a chave.
    $temp = CaminhoDe $env:TEMP ('cofre-estado-' + [Guid]::NewGuid().ToString('N'))

    try {
        New-Item -ItemType Directory -Path $temp -Force | Out-Null
        Copy-Item $ArquivoEstado (CaminhoDe $temp 'estado.json') -Force

        <#
            O ESTADO VAI SEM CIFRA, E ISSO E UMA DECISAO.

            Ele ia por "cofre:", que e o remote CIFRADO. So que cada cartorio
            gera a PROPRIA chave - entao o computador do gerente, com a chave
            dele, nunca conseguiria decifrar o estado de cartorio nenhum. O
            modo gerente nao tinha como funcionar.

            Havia dois caminhos. Usar uma chave unica no parque inteiro faria o
            gerente ler tudo - e um vazamento em um cartorio abriria os 38.
            Recusado.

            O caminho daqui: o BACKUP continua cifrado com a chave de cada
            cartorio, e so o estado sai em claro, por "cofre-s3:", que e o S3
            direto. O gerente le o parque com credencial propria, sem precisar
            da chave de ninguem.

            O QUE FICA VISIVEL para quem entrar no bucket: nome do cartorio,
            nome do servidor, nome dos itens, datas, tamanhos e se deu certo.
            Nada de conteudo de cliente. E a arvore de pastas ja mostrava tudo
            isso, porque directory_name_encryption esta desligado de proposito
            para a estrutura ser legivel no console da AWS.

            Para RESTAURAR um cartorio o gerente continua precisando da chave
            daquele cartorio. Ver o parque e uma coisa; abrir o backup e outra.
        #>
        $r.Destino = "${RemotoSemCifra}:$Bucket/$Cartorio/$Servidor/_estado"

        <#
            STANDARD, e nao DEEP_ARCHIVE.

            O estado precisa ser LIDO toda vez que alguem abre o programa do
            gerente. Em Deep Archive isso levaria de 12 a 48 horas e custaria
            resgate - o painel simplesmente nao funcionaria.

            Sao alguns KB por servidor. Em Standard, 50 cartorios custam
            centavos por mes.
        #>
        $argumentos = @(
            'copy', $temp, $r.Destino
            '--config', $Config
            '--s3-storage-class', 'STANDARD'
            '--retries', '3'
        )

        $exec = RodarRclone -Rclone $Rclone -Argumentos $argumentos
        if ($exec.Codigo -ne 0) { throw $exec.Erro }
        $r.Publicado = $true

    } catch {
        $r.Erro = $_.Exception.Message
    } finally {
        Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
    }

    return $r
}
