<#
================================================================================
  CH.Com Cofre - exportar uma maquina virtual

  O CORACAO DO PROJETO. Tudo o mais e transporte.

  COMO A CONSISTENCIA E OBTIDA

      Export-VM -CaptureLiveState CaptureDataConsistentState

  Na documentacao da Microsoft, esse valor significa "Use Production
  Checkpoint technology". O production checkpoint aciona o VSS DENTRO da
  maquina virtual, pelos Servicos de Integracao: o SQL Server, o Exchange e
  qualquer aplicacao com writer proprio param, gravam o que estava em memoria,
  e so entao o disco e capturado.

  O resultado e application-consistent: a VM restaurada liga como se tivesse
  sido desligada corretamente, nao como se tivesse faltado energia.

  A VM NAO PRECISA SER DESLIGADA. Nao ha janela de indisponibilidade.

  O QUE ISSO NAO E

  Nao e incremental. Cada execucao produz a VM inteira. E o preco de ter
  pontos de recuperacao INDEPENDENTES - nenhum deles depende de outro, o que
  e exatamente o que se quer para Deep Archive, onde ler o que ja subiu custa
  caro e demora horas.

  QUANDO CAI PARA CRASH-CONSISTENT

  Se a VM nao tiver o servico de backup dos Servicos de Integracao ligado, o
  Windows nao consegue fazer production checkpoint e o export vira
  crash-consistent - equivalente a puxar o cabo de energia. Costuma restaurar,
  mas nao ha promessa. O agente detecta e AVISA, em vez de deixar passar.
================================================================================
#>

<#
    Exporta uma VM.

    Devolve um objeto com o resultado. Nunca lanca excecao para o chamador:
    uma VM que falha nao pode derrubar as outras do mesmo host.
#>
function ExportarVM {
    param(
        [Parameter(Mandatory)] $VM,          # objeto vindo de DescobrirAmbiente
        [Parameter(Mandatory)] [string]$PastaDestino
    )

    $res = [PSCustomObject]@{
        Nome         = $VM.Nome
        ID           = [string]$VM.ID
        Sucesso      = $false
        Consistencia = 'desconhecida'
        Pasta        = $null
        TamanhoBytes = 0
        Duracao      = [TimeSpan]::Zero
        Erro         = $null
    }

    $relogio = [Diagnostics.Stopwatch]::StartNew()

    # Uma pasta por VM. O nome vai limpo de caracteres que o Windows recusa e
    # que o S3 trataria como separador de pasta.
    $nomeLimpo = ($VM.Nome -replace '[\/:*?"<>|]', '_').Trim()
    $destino = CaminhoDe $PastaDestino $nomeLimpo

    try {
        if (Test-Path $destino) {
            Passo "limpando export anterior de $($VM.Nome)"
            Remove-Item $destino -Recurse -Force -ErrorAction Stop
        }
        New-Item -ItemType Directory -Path $destino -Force | Out-Null

        <#
            A escolha do modo de captura.

            VM desligada  -> nao ha estado em memoria; o export ja e integro.
            VM ligada com VSS no convidado -> production checkpoint.
            VM ligada sem VSS -> crash-consistent, e o agente diz isso.

            Nao existe opcao "tenta production e cai para crash": o parametro
            e escolhido antes. Por isso a deteccao vem do inventario.
        #>
        if ($VM.Estado -ne 'Running') {
            $modo = 'CaptureCrashConsistentState'
            $res.Consistencia = 'desligada (integra)'
            Passo "exportando $($VM.Nome) - VM desligada"
        } elseif ($VM.VssNoConvidado) {
            $modo = 'CaptureDataConsistentState'
            $res.Consistencia = 'application-consistent'
            Passo "exportando $($VM.Nome) - production checkpoint"
        } else {
            $modo = 'CaptureCrashConsistentState'
            $res.Consistencia = 'CRASH-CONSISTENT'
            Passo "exportando $($VM.Nome) - SEM production checkpoint"
        }

        Export-VM -Name $VM.Nome -Path $destino -CaptureLiveState $modo -ErrorAction Stop

        $res.Pasta = $destino
        $res.TamanhoBytes = TamanhoDaPasta $destino
        $res.Sucesso = $true

    } catch {
        $res.Erro = $_.Exception.Message
        # Deixa a pasta pela metade para tras? Nao: ela ocuparia disco e seria
        # confundida com um export bom na proxima rodada.
        try { if (Test-Path $destino) { Remove-Item $destino -Recurse -Force -ErrorAction SilentlyContinue } } catch { }
    } finally {
        $relogio.Stop()
        $res.Duracao = $relogio.Elapsed
    }

    return $res
}

function TamanhoDaPasta([string]$pasta) {
    $total = 0
    try {
        foreach ($f in @(Get-ChildItem $pasta -Recurse -File -ErrorAction SilentlyContinue)) {
            $total += $f.Length
        }
    } catch { }
    return $total
}
