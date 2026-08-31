<#
================================================================================
  CH.Com Cofre - avisar o painel central

  Cada cartorio manda o resultado para o Painel Backup CH.Com. E assim que o
  gerente ve 50 cartorios numa tela so, em vez de abrir 50 janelas.

  O QUE VAI, E O QUE NAO VAI

  Vai: nome do cartorio, maquina, o que foi protegido, tamanho, se deu certo.
  NAO vai: chave de criptografia, credencial da AWS, nome de arquivo do
  cliente, nem conteudo nenhum. O painel precisa saber SE o backup existe, e
  nao o que tem dentro dele.

  FALHAR AQUI NAO PODE DERRUBAR O BACKUP

  O relatorio e a ultima etapa, e a menos importante. Um painel fora do ar,
  um certificado vencido ou um link caido nao podem transformar um backup bem
  sucedido em falha - por isso tudo aqui e engolido e vira aviso.
================================================================================
#>

function ReportarAoPainel {
    param(
        [Parameter(Mandatory)] [string]$Url,
        [Parameter(Mandatory)] [string]$Token,
        [Parameter(Mandatory)] $Estado,
        [Parameter(Mandatory)] [string]$Cartorio,
        [switch]$AceitarCertificadoInvalido
    )

    $r = [PSCustomObject]@{ Enviado = $false; Erro = $null }

    try {
        # So o resumo. Detalhe de arquivo nao interessa ao painel e seria
        # informacao do cliente viajando sem necessidade.
        $corpo = [ordered]@{
            Produto   = 'CH.Com Cofre'
            Versao    = 1
            Cartorio  = $Cartorio
            Maquina   = $Estado.Maquina
            Comecou   = $Estado.Comecou
            Terminou  = $Estado.Terminou
            Resultado = $Estado.Resultado
            Itens     = $Estado.Itens
            Sucessos  = $Estado.Sucessos
            Falhas    = $Estado.Falhas
            Detalhes  = @(foreach ($d in @($Estado.Detalhes) ) {
                [ordered]@{
                    Tipo         = $d.Tipo
                    Nome         = $d.Nome
                    Sucesso      = $d.Sucesso
                    Consistencia = $d.Detalhe
                    Bytes        = $d.Bytes
                    Quando       = $d.Quando
                }
            })
        }

        if ($AceitarCertificadoInvalido) { IgnorarCertificado }

        $endereco = $Url.TrimEnd('/') + '/api/cofre/' + $Token
        Invoke-RestMethod -Uri $endereco -Method Post -TimeoutSec 45 `
            -ContentType 'application/json; charset=utf-8' `
            -Body ($corpo | ConvertTo-Json -Depth 6) | Out-Null

        $r.Enviado = $true

    } catch {
        $r.Erro = $_.Exception.Message
    } finally {
        if ($AceitarCertificadoInvalido) { RestaurarCertificado }
    }

    return $r
}

<#
    Aceitar certificado proprio, quando o painel estiver com um.

    Isto e uma concessao, e esta isolada aqui de proposito para ficar visivel:
    aceitar qualquer certificado abre espaco para alguem no meio do caminho se
    passar pelo painel. O que viaja aqui e so o resumo do backup, entao o risco
    e pequeno - mas nao e zero, e o certo e o painel ter certificado valido.

    O ajuste e desfeito logo depois, no finally, para nao vazar para o resto
    do processo.
#>
$script:ValidadorAnterior = $null

function IgnorarCertificado {
    $script:ValidadorAnterior = [System.Net.ServicePointManager]::ServerCertificateValidationCallback
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    try {
        [System.Net.ServicePointManager]::SecurityProtocol =
            [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls11
    } catch { }
}

function RestaurarCertificado {
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $script:ValidadorAnterior
}
