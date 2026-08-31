<#
================================================================================
  CH.Com Cofre - validar antes de subir

  A ETAPA QUE DA SENTIDO A PALAVRA "CONCLUIDO".

  Sem isto, "backup concluido" significa apenas "o upload terminou". O
  cartorio fica com uma luz verde no painel e nenhuma garantia de que aquilo
  volta a funcionar. Esse foi o defeito central da arquitetura anterior, e nao
  se repete aqui: NADA SOBE SEM SER VALIDADO ANTES.

  Validar depois nao serve: em Deep Archive, ler o que ja subiu custa dinheiro
  e leva de 12 a 48 horas. A unica hora barata de conferir e enquanto o
  arquivo ainda esta no disco local.

  O QUE CADA CONFERENCIA PROVA

  Compare-VM        que o export e IMPORTAVEL num host Hyper-V. Nao e opiniao:
                    e o mesmo codigo que o Import-VM roda antes de importar.
  gbak -c           que o .fbk restaura de verdade, para um banco de teste.
  RESTORE VERIFYONLY que o .bak do SQL Server esta integro e legivel.
  SHA-256           a impressao digital, gravada num manifesto, para conferir
                    o que voltar da nuvem daqui a meses contra o que saiu daqui.
================================================================================
#>

<#
    O export e importavel?

    Compare-VM e a forma oficial de responder isso sem importar nada. Ele
    devolve um relatorio de incompatibilidades; lista vazia significa que o
    Import-VM funcionaria.

    Um detalhe importante: incompatibilidade NAO e sempre defeito do export.
    Restaurar num host com menos memoria, ou com outro nome de switch de rede,
    aparece aqui - e sao coisas que se ajustam na hora de restaurar. Por isso
    o resultado separa "nao consegui ler" de "leu, com ressalvas".
#>
function ValidarExportDeVM {
    param([Parameter(Mandatory)] [string]$PastaDoExport)

    $r = [PSCustomObject]@{
        Importavel   = $false
        Config       = $null
        Ressalvas    = @()
        Erro         = $null
    }

    # Declarado fora do try para o finally poder limpar mesmo quando o
    # Compare-VM falha no meio.
    $destinoFicticio = $null

    try {
        # O Export-VM grava a configuracao em "Virtual Machines\<GUID>.vmcx".
        # Versoes antigas usavam .xml; aceitar os dois evita quebrar num host
        # mais velho do parque.
        $cfg = @(Get-ChildItem $PastaDoExport -Recurse -File -ErrorAction Stop |
                 Where-Object { $_.Extension -in @('.vmcx', '.xml') } |
                 Where-Object { $_.DirectoryName -like '*Virtual Machines*' })

        if ($cfg.Count -eq 0) {
            $r.Erro = 'o export nao tem arquivo de configuracao de VM dentro'
            return $r
        }

        $r.Config = $cfg[0].FullName

        <#
            -Copy e -GenerateNewId nao sao opcionais aqui.

            Sem eles, o Compare-VM tenta planejar uma importacao COM O MESMO
            identificador da VM original - e recusa com

                "ja existe uma maquina virtual com o mesmo identificador"

            porque a VM original esta rodando no host, ao lado do export.

            Isso foi pego rodando de verdade, e era um defeito grave: um
            export perfeito, application-consistent, de 13 GB, seria marcado
            como "NAO IMPORTAVEL" e o item viraria FALHA no painel. O Cofre
            recusaria o proprio backup bom, todo mes, em todo cartorio.

            E os dois parametros sao os mesmos que a restauracao usa de
            verdade - o procedimento em RESTAURAR-DO-COFRE.txt manda importar
            com -Copy -GenerateNewId. Validar do jeito que se restaura e o
            unico jeito que prova alguma coisa.
        #>
        <#
            E preciso apontar um destino que nao existe.

            Com -Copy, o Compare-VM planeja copiar os discos para o local
            PADRAO do Hyper-V - onde a VM original ja esta. O resultado e
            "o arquivo ... ja existe", e de novo um export bom seria
            reprovado.

            O Compare-VM nao copia nada: ele so monta e devolve o plano. Mas
            valida o destino, entao o destino precisa estar livre. Uma pasta
            com identificador unico resolve, e nada e escrito nela.

            E este e, de novo, o caminho real da restauracao: quem restaura
            aponta outro lugar, porque o original nao existe mais - ou existe
            e nao pode ser sobrescrito.
        #>
        $destinoFicticio = CaminhoDe $env:TEMP ('cofre-validacao-' + [Guid]::NewGuid().ToString('N'))

        $comp = Compare-VM -Path $r.Config -Copy -GenerateNewId `
            -VhdDestinationPath $destinoFicticio `
            -VirtualMachinePath $destinoFicticio `
            -ErrorAction Stop
        $r.Importavel = $true

        foreach ($inc in @($comp.Incompatibilities)) {
            $r.Ressalvas += "$($inc.MessageId): $($inc.Message)"
        }

    } catch {
        $r.Erro = $_.Exception.Message
    } finally {
        # O Compare-VM nao escreve nada no destino - conferido: a pasta fica
        # com zero arquivos. Mas ela E CRIADA, e sem esta limpeza o %TEMP% do
        # servidor iria juntando uma pasta vazia por validacao, todo mes, em
        # todo cartorio.
        if ($destinoFicticio -and (Test-Path $destinoFicticio)) {
            Remove-Item $destinoFicticio -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    return $r
}

<#
    Impressao digital de tudo que vai subir.

    Sem isto nao ha como responder, daqui a oito meses, se o que voltou do
    Deep Archive e o mesmo que saiu do cartorio. O S3 confere o MD5 de cada
    objeto no envio, mas isso prova o transporte, nao o conteudo - e nao
    sobrevive a uma restauracao parcial.

    SHA-256 e lento em arquivo grande (um .vhdx de 100 GB leva minutos), mas
    roda uma vez por rodada e o custo e aceitavel perto de descobrir tarde
    demais que o backup nao presta.
#>
<#
    Normaliza uma pasta para o caminho longo, absoluto e sem barra final.

    Existe por causa de um defeito real, pego em teste: a pasta chegou como

        C:\Users\CAUA-G~1\...\fake      (nome curto 8.3)

    e o Get-ChildItem devolveu os arquivos com o caminho LONGO

        C:\Users\CAUA-GERENTE\...\fake\Virtual Hard Disks\disco.vhdx

    O caminho relativo era calculado com Substring($Pasta.Length), assumindo
    que o FullName comeca exatamente pela pasta. Com os dois tamanhos
    diferentes, o corte saiu no lugar errado e gravou "fake\Virtual Hard
    Disks\..." no manifesto - com a pasta duplicada.

    O efeito seria pior que um erro: na restauracao, a conferencia acusaria
    TODOS os arquivos como faltando, e ninguem saberia se o problema era o
    backup ou o script. Um verificador que sempre reprova nao vale nada.

    Get-Item resolve o nome curto, o relativo e a barra final de uma vez.
#>
function PastaNormalizada([string]$pasta) {
    return (Get-Item -LiteralPath $pasta -ErrorAction Stop).FullName.TrimEnd('\')
}

function GerarManifesto {
    param(
        [Parameter(Mandatory)] [string]$Pasta,
        [Parameter(Mandatory)] [string]$ArquivoManifesto,
        [hashtable]$Extra = @{}
    )

    $Pasta = PastaNormalizada $Pasta
    $itens = @()
    foreach ($f in @(Get-ChildItem $Pasta -Recurse -File -ErrorAction SilentlyContinue)) {
        $rel = $f.FullName.Substring($Pasta.Length).TrimStart('\')
        $hash = ''
        try { $hash = (Get-FileHash -Path $f.FullName -Algorithm SHA256 -ErrorAction Stop).Hash } catch { }
        $itens += [PSCustomObject]@{
            Arquivo = $rel
            Bytes   = $f.Length
            SHA256  = $hash
        }
    }

    $doc = [ordered]@{
        Produto   = 'CH.Com Cofre'
        Versao    = 1
        Maquina   = $env:COMPUTERNAME
        Gerado    = (Get-Date).ToUniversalTime().ToString('o')
        Arquivos  = $itens
        TotalBytes = ($itens | Measure-Object -Property Bytes -Sum).Sum
    }
    foreach ($k in $Extra.Keys) { $doc[$k] = $Extra[$k] }

    $json = $doc | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText($ArquivoManifesto, $json, [System.Text.UTF8Encoding]::new($false))

    return $itens.Count
}

# Confere uma pasta contra um manifesto gerado antes. E o que se roda DEPOIS
# de trazer os arquivos de volta da nuvem, numa restauracao.
function ConferirContraManifesto {
    param(
        [Parameter(Mandatory)] [string]$Pasta,
        [Parameter(Mandatory)] [string]$ArquivoManifesto
    )

    $Pasta = PastaNormalizada $Pasta
    $r = [PSCustomObject]@{ Conferidos = 0; Divergentes = @(); Faltando = @() }
    $doc = Get-Content $ArquivoManifesto -Raw | ConvertFrom-Json

    foreach ($item in @($doc.Arquivos)) {
        $caminho = CaminhoDe $Pasta $item.Arquivo
        if (-not (Test-Path $caminho)) { $r.Faltando += $item.Arquivo; continue }
        $hash = (Get-FileHash -Path $caminho -Algorithm SHA256).Hash
        if ($hash -ne $item.SHA256) { $r.Divergentes += $item.Arquivo }
        else { $r.Conferidos++ }
    }
    return $r
}
