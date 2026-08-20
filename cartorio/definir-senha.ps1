<#
================================================================================
  CH.Com Backup - definir a senha de acesso

  UMA JANELA. VOCE DIGITA A SENHA. PRONTO.

  Sem console para digitar, sem etapa nenhuma no meio. A versao anterior
  perguntava a senha no console e congelava se alguem clicasse dentro da
  janela - e o console tambem nao funcionava em maquina com o banco cifrado
  sem chave. Este caminho nao tem nenhum dos dois problemas.

  COMO FUNCIONA

  O Duplicati aceita --webservice-password para definir a senha, e aceita
  --parameters-file para ler as opcoes de um ARQUIVO em vez da linha de
  comando. Entao a senha:

    - nunca aparece na linha de comando (que qualquer programa da maquina
      consegue ler na lista de processos)
    - nunca aparece em log
    - vive uns tres segundos num arquivo temporario, que e sobrescrito e
      apagado logo depois, inclusive se der erro no meio

  No fim o script CONFERE se a senha funciona mesmo, entrando com ela, e so
  entao diz que deu certo.

  E ele sempre deixa o backup ligado - inclusive se algo falhar no meio.
  Trocar a senha e cosmetico; deixar o cartorio sem backup nao e.

  USO

      Dois cliques em DEFINIR-SENHA.bat

================================================================================
#>

[CmdletBinding()]
param(
    [int]$PortaDuplicati = 8200
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Titulo($t) { Write-Host ""; Write-Host "  $t" -ForegroundColor Cyan }
function Ok($t)     { Write-Host "    $t" -ForegroundColor Green }
function Aviso($t)  { Write-Host "    $t" -ForegroundColor Yellow }
function Erro($t)   { Write-Host "    $t" -ForegroundColor Red }
function Nota($t)   { Write-Host "    $t" -ForegroundColor DarkGray }


# Monta um caminho SEM validar a unidade.
#
# O Join-Path do PowerShell confere se a unidade existe e LANCA erro quando
# nao existe - num servidor sem disco D:, testar "D:\Duplicati 2" derrubava
# o instalador inteiro antes de ele achar o Duplicati em C:. Concatenar nao
# valida nada, que e o que se quer numa lista de lugares POSSIVEIS.
function CaminhoDe([string]$pasta, [string]$arquivo) {
    return ($pasta.TrimEnd('\') + '\' + $arquivo)
}

function AcharDuplicati {
    foreach ($c in @('C:\Program Files\Duplicati 2',
                     'C:\Program Files (x86)\Duplicati 2',
                     "$env:LOCALAPPDATA\Programs\Duplicati 2")) {
        if (Test-Path (CaminhoDe $c 'Duplicati.GUI.TrayIcon.exe')) { return $c }
    }
    throw 'nao encontrei a instalacao do CH.Com Backup nesta maquina.'
}

function NoAr([int]$porta) {
    try { $c = New-Object Net.Sockets.TcpClient; $c.Connect('127.0.0.1', $porta); $c.Close(); return $true }
    catch { return $false }
}

function EsperarSubir([int]$porta, [int]$segundos = 40) {
    for ($i = 0; $i -lt $segundos * 2; $i++) {
        if (NoAr $porta) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

# ------------------------------------------------------------------------------
#  A janela: dois campos, para um erro de digitacao nao trancar o cartorio
#  para fora do proprio backup.
# ------------------------------------------------------------------------------
function PedirSenha {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing

    $f = New-Object Windows.Forms.Form
    $f.Text = 'CH.Com Backup - definir senha'
    $f.Size = New-Object Drawing.Size(440, 250)
    $f.StartPosition = 'CenterScreen'
    $f.FormBorderStyle = 'FixedDialog'
    $f.MaximizeBox = $false; $f.MinimizeBox = $false; $f.TopMost = $true

    $l1 = New-Object Windows.Forms.Label
    $l1.Text = 'Escolha a senha de acesso ao CH.Com Backup deste servidor:'
    $l1.Location = New-Object Drawing.Point(16, 16)
    $l1.Size = New-Object Drawing.Size(400, 20)
    $f.Controls.Add($l1)

    $l2 = New-Object Windows.Forms.Label
    $l2.Text = 'Senha'
    $l2.Location = New-Object Drawing.Point(16, 48)
    $l2.Size = New-Object Drawing.Size(120, 18)
    $f.Controls.Add($l2)

    $t1 = New-Object Windows.Forms.TextBox
    $t1.UseSystemPasswordChar = $true
    $t1.Location = New-Object Drawing.Point(16, 68)
    $t1.Size = New-Object Drawing.Size(396, 24)
    $f.Controls.Add($t1)

    $l3 = New-Object Windows.Forms.Label
    $l3.Text = 'Repita a senha'
    $l3.Location = New-Object Drawing.Point(16, 100)
    $l3.Size = New-Object Drawing.Size(160, 18)
    $f.Controls.Add($l3)

    $t2 = New-Object Windows.Forms.TextBox
    $t2.UseSystemPasswordChar = $true
    $t2.Location = New-Object Drawing.Point(16, 120)
    $t2.Size = New-Object Drawing.Size(396, 24)
    $f.Controls.Add($t2)

    $aviso = New-Object Windows.Forms.Label
    $aviso.ForeColor = [Drawing.Color]::FromArgb(200, 60, 60)
    $aviso.Location = New-Object Drawing.Point(16, 150)
    $aviso.Size = New-Object Drawing.Size(396, 18)
    $f.Controls.Add($aviso)

    $ok = New-Object Windows.Forms.Button
    $ok.Text = 'Definir'
    $ok.Location = New-Object Drawing.Point(236, 174)
    $ok.Size = New-Object Drawing.Size(90, 30)
    $f.Controls.Add($ok); $f.AcceptButton = $ok

    $cancelar = New-Object Windows.Forms.Button
    $cancelar.Text = 'Cancelar'
    $cancelar.Location = New-Object Drawing.Point(334, 174)
    $cancelar.Size = New-Object Drawing.Size(90, 30)
    $cancelar.DialogResult = 'Cancel'
    $f.Controls.Add($cancelar); $f.CancelButton = $cancelar

    $ok.Add_Click({
        if ($t1.Text.Length -lt 8) {
            $aviso.Text = 'Use pelo menos 8 caracteres.'
            return
        }
        if ($t1.Text -ne $t2.Text) {
            $aviso.Text = 'As duas senhas estao diferentes.'
            return
        }
        $f.DialogResult = 'OK'
        $f.Close()
    })

    $f.Add_Shown({ $t1.Focus() })
    if ($f.ShowDialog() -ne 'OK') { return $null }
    return $t1.Text
}

# ==============================================================================

Titulo 'Definir a senha do CH.Com Backup'

$pasta = AcharDuplicati
$tray = Join-Path $pasta 'Duplicati.GUI.TrayIcon.exe'
Ok "encontrado em $pasta"

$senha = PedirSenha
if (-not $senha) { Aviso 'cancelado - nada foi alterado.'; exit 0 }

# Arquivo de parametros: e por aqui que a senha viaja, e nao pela linha de
# comando. Vive alguns segundos e e sobrescrito antes de sumir.
$paramsFile = Join-Path $env:TEMP ('chcom-' + [Guid]::NewGuid().ToString('N') + '.tmp')

function ApagarParametros {
    if (-not (Test-Path $paramsFile)) { return }
    try {
        # sobrescreve antes de apagar: apagar so tira o nome da tabela de
        # arquivos, o conteudo continua no disco ate ser reaproveitado
        $tam = (Get-Item $paramsFile).Length
        [System.IO.File]::WriteAllBytes($paramsFile, (New-Object byte[] $tam))
    } catch { }
    Remove-Item $paramsFile -Force -ErrorAction SilentlyContinue
}

try {
    [System.IO.File]::WriteAllText($paramsFile,
        "--webservice-password=$senha`r`n", [System.Text.UTF8Encoding]::new($false))

    Write-Host ""
    Nota 'reiniciando o CH.Com Backup com a senha nova...'

    # Encerrar de verdade, e CONFERIR. Se o processo continuar vivo, iniciar
    # outro por cima nao troca senha nenhuma: o segundo nao consegue tomar a
    # porta, morre calado, e o script diria que deu certo. Descoberto testando
    # sem elevacao, onde o Stop-Process devolve "Acesso negado".
    Get-Process -Name 'Duplicati.GUI.TrayIcon' -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    $teimoso = @(Get-Process -Name 'Duplicati.GUI.TrayIcon' -ErrorAction SilentlyContinue)
    if ($teimoso.Count -gt 0) {
        throw 'nao consegui encerrar o CH.Com Backup para trocar a senha. ' +
              'Feche esta janela e rode o DEFINIR-SENHA.bat de novo, aceitando ' +
              'o aviso de administrador do Windows.'
    }

    Start-Process -FilePath $tray -ArgumentList "--parameters-file=`"$paramsFile`""

    if (-not (EsperarSubir $PortaDuplicati)) {
        throw "o programa nao voltou a responder na porta $PortaDuplicati."
    }
    Ok 'programa no ar'

    # --- confere de verdade: entra com a senha nova ---------------------------
    Start-Sleep -Seconds 2
    $funcionou = $false
    try {
        $r = Invoke-RestMethod "http://127.0.0.1:$PortaDuplicati/api/v1/auth/login" `
            -Method Post -TimeoutSec 20 -ContentType 'application/json' `
            -Body (@{ Password = $senha; RememberMe = $false } | ConvertTo-Json)
        $funcionou = [bool]$r.AccessToken
    } catch { $funcionou = $false }

    Write-Host ""
    if ($funcionou) {
        Write-Host "  ============================================" -ForegroundColor Green
        Write-Host "    SENHA DEFINIDA E CONFERIDA" -ForegroundColor Green
        Write-Host "  ============================================" -ForegroundColor Green
        Write-Host ""
        Nota "Entre em http://localhost:$PortaDuplicati com ela."
        Nota 'Anote no seu cofre de senhas, junto do nome do cartorio.'
        Nota 'Ela nao pode ser recuperada depois - so trocada rodando isto de novo.'
    } else {
        Aviso 'a senha foi enviada, mas a conferencia nao passou.'
        Nota 'Tente entrar em http://localhost:' + $PortaDuplicati + ' com ela.'
        Nota 'Se nao entrar, abra pelo icone ao lado do relogio e defina em Configuracoes.'
    }
} catch {
    Write-Host ""
    Erro $_.Exception.Message
} finally {
    ApagarParametros
    $senha = $null
    [GC]::Collect()

    # O backup vem antes de qualquer outra coisa: se sobrou o programa
    # parado por causa de uma troca de senha, isso e pior que a senha velha.
    if (-not (NoAr $PortaDuplicati)) {
        Write-Host ""
        Aviso 'o programa nao estava no ar - ligando de volta.'
        try {
            Start-Process -FilePath $tray
            if (EsperarSubir $PortaDuplicati 30) { Ok 'BACKUP NO AR' }
            else { Erro 'NAO subiu. Abra o CH.Com Backup pelo menu Iniciar.' }
        } catch { Erro "nao consegui iniciar: $($_.Exception.Message)" }
    }
}
