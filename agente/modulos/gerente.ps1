<#
================================================================================
  CH.Com Cofre - o modo gerente

  Le o estado de TODOS os cartorios direto do bucket. E o que substitui o
  painel-servidor.

  COMO FUNCIONA

  Cada agente publica o proprio estado em

      backup-aws-ch/<CARTORIO>/<SERVIDOR>/_estado/estado.json

  Este modulo traz todos de uma vez e monta a visao do parque. Nenhum
  servidor no meio: quem tem a credencial de leitura do bucket ve tudo, de
  qualquer maquina, sem nada exposto na internet.

  UMA CHAMADA, E NAO UMA POR CARTORIO

  Com 50 cartorios e varios servidores em cada, ler um por um seria uma
  chamada de rede por servidor - lento e caro em requisicoes. O rclone copia
  todos os estado.json numa passada so, com um filtro, e a leitura acontece
  em disco local.
================================================================================
#>

<#
    Traz os estados de todos os cartorios.

    Devolve uma lista de objetos com cartorio, servidor e o estado lido,
    mais o que deu errado - porque um cartorio que nao aparece e a
    informacao mais importante da tela, e nao pode sumir em silencio.
#>
function LerParque {
    param(
        [Parameter(Mandatory)] [string]$Rclone,
        [Parameter(Mandatory)] [string]$Config,
        # Le o S3 DIRETO, e nao o remote cifrado: o estado de cada cartorio e
        # publicado em claro justamente para o gerente nao precisar da chave
        # de ninguem. Ver PublicarEstado.
        [string]$RemotoSemCifra = 'cofre-s3',
        [Parameter(Mandatory)] [string]$Bucket,
        [int]$SegundosLimite = 120
    )

    $r = [PSCustomObject]@{
        Servidores = @()
        Erro       = $null
        LidoEm     = (Get-Date)
    }

    $temp = CaminhoDe $env:TEMP ('cofre-parque-' + [Guid]::NewGuid().ToString('N'))

    try {
        New-Item -ItemType Directory -Path $temp -Force | Out-Null

        <#
            O filtro pega so os estados, e nada mais.

            Sem ele, o copy traria o backup inteiro do parque - centenas de
            gigabytes, congelados em Deep Archive, com custo de resgate. O
            "--include" limita a busca aos arquivos que interessam.

            --max-depth 4 corta a varredura em <cartorio>/<servidor>/_estado/
            /arquivo: sem isso o rclone desceria por todas as pastas de data
            de todos os cartorios so para descobrir que nao ha nada la.
        #>
        $argumentos = @(
            'copy', "${RemotoSemCifra}:$Bucket", $temp
            '--config', $Config
            '--include', '*/*/_estado/estado.json'
            '--max-depth', '4'
            '--retries', '2'
        )

        $exec = RodarRclone -Rclone $Rclone -Argumentos $argumentos
        if ($exec.Codigo -ne 0) { throw $exec.Erro }

        # A estrutura veio junto: <cartorio>\<servidor>\_estado\estado.json
        foreach ($arq in @(Get-ChildItem $temp -Filter 'estado.json' -Recurse -File -ErrorAction SilentlyContinue)) {
            $pastaEstado = Split-Path $arq.FullName -Parent
            $pastaServidor = Split-Path $pastaEstado -Parent
            $pastaCartorio = Split-Path $pastaServidor -Parent

            $item = [PSCustomObject]@{
                Cartorio = Split-Path $pastaCartorio -Leaf
                Servidor = Split-Path $pastaServidor -Leaf
                Estado   = $null
                Erro     = $null
            }

            try {
                $item.Estado = Get-Content $arq.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            } catch {
                # Estado ilegivel e um problema para mostrar, nao para
                # esconder: significa que aquele servidor esta gravando algo
                # que ninguem consegue ler.
                $item.Erro = "estado ilegivel: $($_.Exception.Message)"
            }

            $r.Servidores += $item
        }

    } catch {
        $r.Erro = $_.Exception.Message
    } finally {
        Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
    }

    return $r
}

<#
    Resume um servidor numa linha, do jeito que a tela precisa.

    A pergunta que a tela responde nao e "o ultimo backup deu certo?", e sim
    "ha quanto tempo este servidor nao manda noticia?".

    Um servidor que subiu tudo perfeitamente ha tres meses e um servidor que
    parou - mas o estado dele diz "sucesso". Sem olhar a DATA, ele apareceria
    verde para sempre.
#>
function ResumirServidor($item) {
    $r = [PSCustomObject]@{
        Cartorio     = $item.Cartorio
        Servidor     = $item.Servidor
        Estado       = 'sem-dados'
        Frase        = ''
        Detalhe      = ''
        Quando       = $null
        Dias         = $null
        Itens        = 0
        Falhas       = 0
        CrashConsist = 0
        Bytes        = 0
    }

    if ($item.Erro) {
        $r.Estado = 'erro'
        $r.Frase = 'estado ilegivel'
        $r.Detalhe = $item.Erro
        return $r
    }

    $e = $item.Estado
    if (-not $e) {
        $r.Estado = 'erro'
        $r.Frase = 'sem estado'
        return $r
    }

    $r.Itens = [int]$e.Itens
    $r.Falhas = [int]$e.Falhas

    foreach ($d in @($e.Detalhes)) {
        if ($d.Sucesso) { $r.Bytes += [long]$d.Bytes }
        if ($d.Sucesso -and ([string]$d.Detalhe).ToUpper().Contains('CRASH')) { $r.CrashConsist++ }
    }

    if ($e.Terminou) {
        try {
            $r.Quando = DataOuNada $e.Terminou
            $r.Dias = [int]((Get-Date) - $r.Quando).TotalDays
        } catch { }
    }

    <#
        A ordem das perguntas importa.

        Primeiro "chegou noticia?", depois "a noticia e boa?". Um servidor
        que nao reporta ha 60 dias e vermelho mesmo que a ultima noticia
        tenha sido de sucesso total - porque o que se sabe dele tem 60 dias.

        Os prazos: os bancos sobem todo dia, as VMs uma vez por mes. 40 dias
        sem NENHUMA noticia ja significa que ate a rodada mensal falhou.
    #>
    if ($null -eq $r.Dias) {
        $r.Estado = 'erro'; $r.Frase = 'sem data'
    } elseif ($r.Dias -gt 40) {
        $r.Estado = 'erro'
        $r.Frase = "sem noticia ha $($r.Dias) dias"
        $r.Detalhe = 'o agente parou de reportar, ou o servidor esta fora do ar'
    } elseif ($e.Falhas -gt 0) {
        $r.Estado = 'erro'
        $r.Frase = "$($e.Falhas) item(ns) falharam"
        $r.Detalhe = "$($e.Sucessos) de $($e.Itens) enviados"
    } elseif ($r.Dias -gt 8) {
        $r.Estado = 'aviso'
        $r.Frase = "ultima copia ha $($r.Dias) dias"
        $r.Detalhe = 'os bancos deveriam subir todo dia'
    } elseif ($r.CrashConsist -gt 0) {
        $r.Estado = 'aviso'
        $r.Frase = "$($r.CrashConsist) item(ns) sem garantia"
        $r.Detalhe = 'copiados como se tivesse faltado energia - faltam os Servicos de Integracao'
    } else {
        $r.Estado = 'ok'
        $r.Frase = 'em dia'
        $r.Detalhe = "$($e.Itens) item(ns), $(Tamanho $r.Bytes)"
    }

    return $r
}
