<#
================================================================================
  CH.Com Cofre - desinstalacao

  Tira o programa, os atalhos, o registro e o agendamento.

  O QUE ELE NAO APAGA, E POR QUE

  As copias na AWS. Desinstalar o programa de um servidor nao pode apagar o
  backup do cartorio - isso seria transformar uma limpeza de rotina numa
  perda irreversivel. Para remover os dados da nuvem, use o console da AWS,
  de proposito e conscientemente.

  E ele AVISA sobre a chave antes de sair: sem ela, o que ficou na AWS nao
  pode ser lido por ninguem.
================================================================================
#>

[CmdletBinding()]
param([switch]$SemPerguntar)

$ErrorActionPreference = 'Continue'
$raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $raiz 'modulos\comum.ps1')

# Onde ficam configuracao, estado e historico. NAO e a pasta do codigo:
# Program Files e somente leitura para quem nao e administrador.
$dados = PastaDeDados $raiz

DesligarCliqueQueTrava
Marca
Titulo 'Desinstalar o CH.Com Cofre'

if (-not (EhAdministrador)) {
    Erro 'precisa ser executado como Administrador.'
    exit 1
}

$temConfig = Test-Path (CaminhoDe $dados 'rclone.conf')
if ($temConfig) {
    Write-Host ''
    Caixa @('ATENCAO: HA COPIAS NA AWS',
            '',
            'Desinstalar NAO apaga o que esta na nuvem, e NAO apaga a chave',
            'que ja foi guardada fora daqui.',
            '',
            'Mas a copia da chave que existe NESTE servidor sera apagada.',
            'Se ela nao estiver no seu cofre de senhas, as copias na AWS',
            'ficam ilegiveis para sempre.') 'Yellow'
}

if (-not $SemPerguntar) {
    $r = Read-Host '    Digite REMOVER para confirmar a desinstalacao'
    if ($r.Trim().ToUpper() -ne 'REMOVER') { Aviso 'cancelado.'; exit 0 }
}

Titulo 'Removendo'

foreach ($t in @('CH.Com Cofre - diario', 'CH.Com Cofre - mensal')) {
    try {
        Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction Stop
        Ok "tarefa removida: $t"
    } catch { }
}

try {
    Get-Process powershell -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowTitle -like '*CH.Com Cofre*' } |
        Stop-Process -Force -ErrorAction SilentlyContinue
} catch { }

try {
    Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' `
        -Name 'CH.Com Cofre' -ErrorAction SilentlyContinue
    Ok 'icone da bandeja tirado do boot'
} catch { }

foreach ($a in @(
    (CaminhoDe ([Environment]::GetFolderPath('CommonDesktopDirectory')) 'CH.Com Cofre.lnk'),
    (CaminhoDe (CaminhoDe ([Environment]::GetFolderPath('CommonPrograms')) 'CH.Com') 'CH.Com Cofre.lnk')
)) {
    if (Test-Path $a) { Remove-Item $a -Force -ErrorAction SilentlyContinue }
}
Ok 'atalhos removidos'

try {
    Remove-Item 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\CHComCofre' `
        -Recurse -Force -ErrorAction SilentlyContinue
    Ok 'registro removido'
} catch { }

# A chave e sobrescrita antes de sumir: apagar so tira o nome da tabela de
# arquivos, o conteudo continua no disco ate ser reaproveitado.
$conf = CaminhoDe $dados 'rclone.conf'
if (Test-Path $conf) {
    try {
        $tam = (Get-Item $conf).Length
        [System.IO.File]::WriteAllBytes($conf, (New-Object byte[] $tam))
    } catch { }
    Remove-Item $conf -Force -ErrorAction SilentlyContinue
    Ok 'chave removida deste servidor'
}

Write-Host ''
Caixa @('CH.Com COFRE REMOVIDO',
        '',
        'As copias na AWS continuam la, intactas.',
        'A pasta do programa pode ser apagada a mao.') 'Green'
Nota $raiz
Write-Host ''
Read-Host '    Enter para fechar' | Out-Null
