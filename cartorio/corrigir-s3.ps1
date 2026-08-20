# =============================================================================
#  Corrige destinos "s3-aws://" para "s3://" nos backups do Duplicati.
#
#  O QUE ESTE ERRO E
#
#    "The backend protocol s3-aws is not supported"
#
#  O Duplicati registra o backend S3 com o nome "s3" (ver S3Backend.cs, campo
#  ProtocolKey). "s3-aws" nao existe como protocolo: "aws" e o valor de uma
#  OPCAO (--s3-client=aws|minio), nao um esquema de endereco.
#
#  Um backup gravado com "s3-aws://" e recusado ANTES de o Duplicati tentar
#  conectar. Ele nao roda, e o backup daquele servidor fica parado.
#
#  A correcao e trocar o comeco do endereco e nada mais. Bucket, regiao,
#  caminho, credenciais e opcoes continuam iguais, e os arquivos que ja estao
#  na AWS continuam la: o Duplicati reencontra tudo no mesmo lugar.
# =============================================================================

[CmdletBinding()]
param(
    [int]$PortaDuplicati = 8200,
    [string]$SenhaDuplicati,
    [switch]$Aplicar   # sem isto, so MOSTRA o que faria
)

$ErrorActionPreference = 'Stop'

function Titulo($t) { Write-Host ""; Write-Host "  $t" -ForegroundColor Cyan }
function Ok($t)     { Write-Host "    $t" -ForegroundColor Green }
function Aviso($t)  { Write-Host "    $t" -ForegroundColor Yellow }
function Erro($t)   { Write-Host "    $t" -ForegroundColor Red }

function Pedir-Senha {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    } catch {
        return (Read-Host "    Senha do Duplicati")
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'CH.Com Backup - senha do Duplicati'
    $form.Size = New-Object System.Drawing.Size(430, 200)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false; $form.MinimizeBox = $false; $form.TopMost = $true

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Location = New-Object System.Drawing.Point(15, 15)
    $lbl.Size = New-Object System.Drawing.Size(390, 40)
    $lbl.Text = "Digite a senha de acesso do Duplicati deste servidor."
    $form.Controls.Add($lbl)

    $cx = New-Object System.Windows.Forms.TextBox
    $cx.Location = New-Object System.Drawing.Point(15, 60)
    $cx.Size = New-Object System.Drawing.Size(390, 25)
    $cx.UseSystemPasswordChar = $true
    $form.Controls.Add($cx)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Location = New-Object System.Drawing.Point(215, 105)
    $ok.Size = New-Object System.Drawing.Size(90, 30)
    $ok.Text = 'Continuar'
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Controls.Add($ok); $form.AcceptButton = $ok

    $ca = New-Object System.Windows.Forms.Button
    $ca.Location = New-Object System.Drawing.Point(315, 105)
    $ca.Size = New-Object System.Drawing.Size(90, 30)
    $ca.Text = 'Cancelar'
    $ca.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($ca); $form.CancelButton = $ca

    $form.Add_Shown({ $form.Activate(); $cx.Focus() })
    $r = $form.ShowDialog()
    $s = $cx.Text
    $form.Dispose()
    if ($r -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
    return $s
}

Write-Host ""
Write-Host "  ===============================================================" -ForegroundColor Cyan
Write-Host "     Corrigir destino s3-aws:// dos backups" -ForegroundColor Cyan
Write-Host "  ===============================================================" -ForegroundColor Cyan

$base = "http://127.0.0.1:$PortaDuplicati"

# --- o Duplicati esta no ar? -------------------------------------------------
$noAr = $false
$c = New-Object System.Net.Sockets.TcpClient
try { $c.Connect('127.0.0.1', $PortaDuplicati); $noAr = $c.Connected } catch { } finally { $c.Close() }

if (-not $noAr) {
    Erro "O Duplicati nao esta respondendo em $base"
    Write-Host "    Abra o Duplicati e rode este script de novo."
    Write-Host "    Se ele usa outra porta:  -PortaDuplicati 8300"
    exit 1
}

# --- login -------------------------------------------------------------------
if (-not $SenhaDuplicati) {
    $SenhaDuplicati = Pedir-Senha
    if (-not $SenhaDuplicati) { Aviso "Cancelado. Nada foi alterado."; exit 0 }
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try {
    $login = Invoke-RestMethod "$base/api/v1/auth/login" -Method Post -TimeoutSec 20 `
             -ContentType 'application/json' -Body (@{ Password = $SenhaDuplicati } | ConvertTo-Json)
    $cab = @{ Authorization = "Bearer $($login.AccessToken)" }
} catch {
    Erro "Senha recusada pelo Duplicati. Nada foi alterado."
    exit 1
}

# --- procurar backups com s3-aws:// -------------------------------------------
Titulo "Procurando backups com destino s3-aws://"

$lista = Invoke-RestMethod "$base/api/v1/backups" -Headers $cab -TimeoutSec 30
$afetados = @()

foreach ($item in $lista) {
    $b = $item.Backup
    if (-not $b) { continue }
    if ($b.TargetURL -like 's3-aws://*') {
        $afetados += [pscustomobject]@{
            ID    = $b.ID
            Nome  = $b.Name
            Antes = $b.TargetURL
            Depois = 's3://' + $b.TargetURL.Substring('s3-aws://'.Length)
        }
    }
}

if ($afetados.Count -eq 0) {
    Ok "nenhum backup com s3-aws:// encontrado"
    Write-Host ""
    Write-Host "    Se o erro continua, veja o destino na tela do backup:"
    Write-Host "    ele precisa comecar com s3://"
    Write-Host ""
    exit 0
}

Write-Host ""
foreach ($a in $afetados) {
    Write-Host "    Backup: $($a.Nome)" -ForegroundColor White
    Write-Host "      antes : $($a.Antes)" -ForegroundColor Red
    Write-Host "      depois: $($a.Depois)" -ForegroundColor Green
    Write-Host ""
}

if (-not $Aplicar) {
    Write-Host "  ===============================================================" -ForegroundColor Yellow
    Write-Host "     ISTO FOI SO UMA SIMULACAO - nada foi alterado" -ForegroundColor Yellow
    Write-Host "     Para aplicar de verdade, rode o CORRIGIR-S3.bat" -ForegroundColor Yellow
    Write-Host "  ===============================================================" -ForegroundColor Yellow
    Write-Host ""
    exit 0
}

# --- aplicar ------------------------------------------------------------------
Titulo "Aplicando a correcao"

foreach ($a in $afetados) {
    try {
        # Le a configuracao INTEIRA e devolve inteira, trocando so o TargetURL.
        # Montar um objeto novo aqui apagaria filtros, agendamento e opcoes
        # avancadas que nao conhecemos.
        $det = Invoke-RestMethod "$base/api/v1/backup/$($a.ID)" -Headers $cab -TimeoutSec 30
        $cfg = if ($det.data) { $det.data } else { $det }

        # Guarda a configuracao original em disco antes de mexer. Se algo sair
        # errado, da para consultar exatamente como estava.
        $bkp = Join-Path $env:TEMP "chcom-backup-config-$($a.ID)-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
        ($cfg | ConvertTo-Json -Depth 20) | Out-File $bkp -Encoding utf8
        Ok "copia da configuracao salva em: $bkp"

        $cfg.Backup.TargetURL = $a.Depois

        Invoke-RestMethod "$base/api/v1/backup/$($a.ID)" -Method Put -Headers $cab `
            -ContentType 'application/json' -Body ($cfg | ConvertTo-Json -Depth 20) -TimeoutSec 60 | Out-Null

        Ok "'$($a.Nome)' corrigido"
    } catch {
        Erro "falhou em '$($a.Nome)': $($_.Exception.Message)"
    }
}

# --- conferir -----------------------------------------------------------------
Titulo "Conferindo"

$lista2 = Invoke-RestMethod "$base/api/v1/backups" -Headers $cab -TimeoutSec 30
$restantes = @($lista2 | Where-Object { $_.Backup.TargetURL -like 's3-aws://*' })

Write-Host ""
if ($restantes.Count -eq 0) {
    Write-Host "  ===============================================================" -ForegroundColor Green
    Write-Host "     CORRIGIDO" -ForegroundColor Green
    Write-Host "  ===============================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "    AGORA FACA ISTO, nesta ordem:"
    Write-Host ""
    Write-Host "    1. Abra o backup na tela do Duplicati"
    Write-Host "    2. Va ate Destino e clique em 'Testar conexao'"
    Write-Host "    3. So depois de o teste passar, rode o backup manualmente"
    Write-Host ""
    Write-Host "    Nao espere o horario agendado para descobrir se funcionou."
} else {
    Erro "ainda restam $($restantes.Count) backup(s) com s3-aws://"
    foreach ($r in $restantes) { Write-Host "      $($r.Backup.Name)" }
}
Write-Host ""
