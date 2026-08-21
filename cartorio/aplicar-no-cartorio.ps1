# =============================================================================
#  CH.Com Backup - aplicar no servidor do cartorio
#
#  Aplica a identidade visual da CH.Com no Duplicati ja instalado e configura
#  o envio de relatorios para o Painel Backup CH.Com.
#
#  COMO USAR
#
#    1. Copie esta pasta inteira para o servidor do cartorio
#    2. Clique com o botao direito no PowerShell e escolha
#       "Executar como administrador"
#    3. Rode:
#
#         cd <pasta onde voce copiou>
#         .\aplicar-no-cartorio.ps1 -Token SEU-TOKEN -UrlPainel https://painel.chcom.com.br
#
#       O token aparece na tela do cartorio dentro do painel.
#
#  Para so aplicar a marca, sem configurar o envio, rode sem -Token.
#  Para desfazer tudo:  .\aplicar-no-cartorio.ps1 -Desfazer
# =============================================================================

[CmdletBinding()]
param(
    [string]$Token,
    [string]$UrlPainel,
    [string]$SenhaDuplicati,
    [string]$Destino = 'C:\Program Files\Duplicati 2',
    # A porta em que o Duplicati atende. 8200 é o padrão, mas há cartório com
    # outra configurada — se estiver errada, o script aplica a marca e depois
    # falha ao configurar o envio, sem motivo aparente.
    [int]$PortaDuplicati = 8200,
    [switch]$Desfazer,
    [switch]$AceitarCertificadoInvalido
)

$ErrorActionPreference = 'Stop'
$pasta = $PSScriptRoot

# $backup depende de $Destino, que pode mudar na deteccao automatica logo
# abaixo. Por isso ele so e calculado depois que $Destino esta definitivo.
$backup = $null

function Titulo($t) { Write-Host ""; Write-Host "  $t" -ForegroundColor Cyan }
function Ok($t)     { Write-Host "    $t" -ForegroundColor Green }
function Aviso($t)  { Write-Host "    $t" -ForegroundColor Yellow }
function Erro($t)   { Write-Host "    $t" -ForegroundColor Red }

<#
    Pede a senha numa JANELA, não no console.

    O caminho óbvio seria Read-Host -AsSecureString, e ele foi trocado por um
    motivo concreto: o console do Windows vem com o QuickEdit ligado, e
    qualquer clique dentro da janela coloca o console em modo de seleção, o
    que CONGELA o programa até alguém apertar Esc. Some a isso que a senha
    oculta não mostra nem asterisco, e o resultado é uma instalação que parece
    travada sem estar — e o técnico aborta uma execução que ia bem.

    A janela gráfica não congela com clique, mostra asteriscos, tem botão de
    Cancelar e aceita Enter e Esc. Se o Windows Forms não estiver disponível
    (Server Core, por exemplo), cai no Read-Host, que continua funcionando.
#>
function Pedir-Senha {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    } catch {
        Write-Host ""
        Aviso "Sem interface grafica; pedindo a senha aqui no terminal."
        Aviso "Os caracteres NAO aparecem enquanto voce digita. Isso e normal."
        $s = Read-Host "    Senha do Duplicati"
        return $s
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'CH.Com Backup - senha do Duplicati'
    $form.Size = New-Object System.Drawing.Size(430, 210)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.TopMost = $true   # senão some atrás da janela do PowerShell

    $texto = New-Object System.Windows.Forms.Label
    $texto.Location = New-Object System.Drawing.Point(15, 15)
    $texto.Size = New-Object System.Drawing.Size(390, 45)
    $texto.Text = "Digite a senha de acesso do Duplicati deste servidor.`n" +
                  "E a mesma que voce usa para abrir o Duplicati no navegador."
    $form.Controls.Add($texto)

    $caixa = New-Object System.Windows.Forms.TextBox
    $caixa.Location = New-Object System.Drawing.Point(15, 70)
    $caixa.Size = New-Object System.Drawing.Size(390, 25)
    $caixa.UseSystemPasswordChar = $true
    $form.Controls.Add($caixa)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Location = New-Object System.Drawing.Point(215, 115)
    $ok.Size = New-Object System.Drawing.Size(90, 30)
    $ok.Text = 'Continuar'
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Controls.Add($ok)
    $form.AcceptButton = $ok

    $cancelar = New-Object System.Windows.Forms.Button
    $cancelar.Location = New-Object System.Drawing.Point(315, 115)
    $cancelar.Size = New-Object System.Drawing.Size(90, 30)
    $cancelar.Text = 'Cancelar'
    $cancelar.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancelar)
    $form.CancelButton = $cancelar

    $form.Add_Shown({ $form.Activate(); $caixa.Focus() })

    Write-Host ""
    Write-Host "    Abri uma janela pedindo a senha do Duplicati." -ForegroundColor Cyan
    Write-Host "    Se nao estiver visivel, procure na barra de tarefas." -ForegroundColor Cyan

    $r = $form.ShowDialog()
    $senha = $caixa.Text
    $form.Dispose()

    if ($r -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
    return $senha
}

# --- verificacoes -----------------------------------------------------------

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Erro "Este script precisa ser executado como Administrador."
    Erro "Feche, clique com o botao direito no PowerShell e escolha 'Executar como administrador'."
    exit 1
}

<#
    Descobre onde o Duplicati esta instalado.

    Assumir "C:\Program Files\Duplicati 2" nao serve: cada servidor instala
    onde quer, e ha instalacao por usuario (em AppData), em outro disco, e em
    pasta renomeada. Num parque de dezenas de servidores isso e regra, nao
    excecao.

    A ordem abaixo vai do mais confiavel para o mais generico. O primeiro
    item e o melhor de todos: se o Duplicati esta RODANDO, o proprio sistema
    diz onde o executavel esta, sem chute nenhum.
#>
# Monta um caminho SEM validar a unidade.
#
# O Join-Path do PowerShell confere se a unidade existe e LANCA erro quando
# ela nao existe. Num servidor sem disco D:, testar "D:\Duplicati 2" na lista
# de lugares possiveis derrubava o instalador ANTES de ele achar o Duplicati
# em C: - e o tecnico via "TERMINOU COM AVISO" numa maquina onde estava tudo
# certo. Concatenar nao valida, que e o que se quer numa lista de lugares
# POSSIVEIS.
#
# O nome nao e "Juntar" porque ja existe uma funcao com esse nome neste
# arquivo, que junta URLs de relatorio - e as duas coisas nao tem relacao.
function CaminhoDe([string]$pasta, [string]$arquivo) {
    return ($pasta.TrimEnd('\') + '\' + $arquivo)
}

function Achar-Duplicati {
    $candidatos = @()

    # 1. processo em execucao — a fonte mais confiavel
    foreach ($nome in @('Duplicati.GUI.TrayIcon', 'Duplicati.Server', 'Duplicati.WindowsService')) {
        $p = Get-Process -Name $nome -ErrorAction SilentlyContinue
        foreach ($x in $p) {
            try { if ($x.Path) { $candidatos += Split-Path $x.Path -Parent } } catch { }
        }
    }

    # 2. servico instalado — le o caminho do binario registrado
    try {
        $svcs = Get-CimInstance Win32_Service -Filter "Name LIKE '%Duplicati%'" -ErrorAction Stop
        foreach ($s in $svcs) {
            if ($s.PathName) {
                $limpo = $s.PathName.Trim('"').Split('"')[0]
                if (Test-Path $limpo) { $candidatos += Split-Path $limpo -Parent }
            }
        }
    } catch { }

    # 3. registro de programas instalados (32 e 64 bits, maquina e usuario)
    $chaves = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($k in $chaves) {
        try {
            Get-ItemProperty $k -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -like '*Duplicati*' -and $_.InstallLocation } |
                ForEach-Object { $candidatos += $_.InstallLocation.TrimEnd('\') }
        } catch { }
    }

    # 4. caminhos comuns
    $candidatos += @(
        "$env:ProgramFiles\CH.Com Backup 2"
        "$env:ProgramFiles\Duplicati 2"
        "${env:ProgramFiles(x86)}\CH.Com Backup 2"
        "${env:ProgramFiles(x86)}\Duplicati 2"
        "$env:LOCALAPPDATA\Programs\Duplicati 2"
        "$env:ProgramFiles\Duplicati"
        'C:\Duplicati 2'
        'D:\Duplicati 2'
    )

    # Vale o primeiro que realmente tenha o executavel dentro. Uma pasta que
    # existe mas nao tem o Duplicati dentro nao serve de nada.
    foreach ($c in ($candidatos | Where-Object { $_ } | Select-Object -Unique)) {
        if (Test-Path (CaminhoDe $c 'Duplicati.GUI.TrayIcon.exe')) { return $c }
    }
    foreach ($c in ($candidatos | Where-Object { $_ } | Select-Object -Unique)) {
        if (Test-Path (CaminhoDe $c 'Duplicati.Server.exe')) { return $c }
    }

    return $null
}

# Só procura sozinho se o operador não disse onde fica.
if (-not $PSBoundParameters.ContainsKey('Destino')) {
    Titulo "Procurando o Duplicati neste servidor"
    $achado = Achar-Duplicati
    if ($achado) {
        $Destino = $achado
        Ok "encontrado em: $Destino"
    }
}

<#
    Instala o Duplicati quando ele nao existe no servidor.

    Um instalador que exige o programa ja instalado nao instala nada. Aqui o
    tecnico chega num servidor limpo, da um duplo clique, e sai com o CH.Com
    Backup funcionando.

    Duas fontes, nesta ordem:

    1. Um .msi dentro da pasta do pacote. Serve para servidor sem internet, e
       tambem para fixar a versao: basta o tecnico levar o .msi junto.
    2. Baixar do GitHub oficial do Duplicati.

    A instalacao e silenciosa (/qn). O log do msiexec fica guardado ao lado,
    porque quando um MSI falha o codigo de saida sozinho nao diz o motivo.
#>
function Instalar-Duplicati {
    # --- 1. .msi que veio junto no pacote -----------------------------------
    $local = Get-ChildItem $pasta -Filter '*.msi' -File -ErrorAction SilentlyContinue |
             Sort-Object Length -Descending | Select-Object -First 1

    if ($local) {
        Ok "usando o instalador que veio na pasta: $($local.Name)"
        return (Instalar-Msi $local.FullName)
    }

    # --- 2. baixar do GitHub oficial ----------------------------------------
    Titulo "Baixando o Duplicati do site oficial"
    Write-Host "    (sao cerca de 80 MB, pode levar alguns minutos)"

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $url = $null
    try {
        # A API devolve os releases em ordem; pegamos o primeiro que tenha um
        # instalador Windows x64 com interface. Filtrar por "stable" evita
        # entregar uma canary a um cartorio.
        $releases = Invoke-RestMethod 'https://api.github.com/repos/duplicati/duplicati/releases' `
                    -Headers @{ 'User-Agent' = 'CH.Com-Backup-Instalador' } -TimeoutSec 60

        foreach ($r in $releases) {
            if ($r.prerelease) { continue }
            $a = $r.assets | Where-Object {
                $_.name -like '*win-x64-gui*.msi' -and $_.name -like '*stable*'
            } | Select-Object -First 1
            if (-not $a) {
                $a = $r.assets | Where-Object { $_.name -like '*win-x64-gui*.msi' } | Select-Object -First 1
            }
            if ($a) { $url = $a.browser_download_url; $nomeArq = $a.name; break }
        }
    } catch {
        Erro "nao consegui consultar o site do Duplicati: $($_.Exception.Message)"
    }

    if (-not $url) {
        Erro "Nao consegui descobrir o link do instalador do Duplicati."
        Write-Host ""
        Write-Host "    Este servidor pode estar sem internet ou com o acesso bloqueado."
        Write-Host ""
        Write-Host "    SOLUCAO: baixe o instalador em outro computador, em"
        Write-Host "      https://duplicati.com/download   (versao Windows 64-bit .msi)"
        Write-Host "    copie o arquivo .msi para DENTRO desta pasta:"
        Write-Host "      $pasta"
        Write-Host "    e rode o INSTALAR.bat de novo. Ele usa o arquivo local."
        return $false
    }

    $destinoMsi = Join-Path $env:TEMP $nomeArq
    Ok "versao: $nomeArq"

    try {
        # ProgressPreference silencioso: a barra do Invoke-WebRequest deixa o
        # download varias vezes mais lento em PowerShell 5.
        $antes = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest $url -OutFile $destinoMsi -UseBasicParsing -TimeoutSec 1800
        $ProgressPreference = $antes
    } catch {
        Erro "falha ao baixar: $($_.Exception.Message)"
        return $false
    }

    $mb = [math]::Round((Get-Item $destinoMsi).Length / 1MB, 1)
    Ok "baixado ($mb MB)"

    return (Instalar-Msi $destinoMsi)
}

function Instalar-Msi([string]$caminho) {
    Titulo "Instalando o Duplicati"
    Write-Host "    isso leva um ou dois minutos, nao feche esta janela"

    $logMsi = Join-Path $env:TEMP 'chcom-instalacao-duplicati.log'
    $p = Start-Process msiexec.exe `
         -ArgumentList "/i `"$caminho`" /qn /norestart /l*v `"$logMsi`"" `
         -Wait -PassThru

    # 0 = ok, 3010 = instalou e pede reinicio (aceitavel, o Duplicati roda)
    if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010) {
        Ok "Duplicati instalado"
        if ($p.ExitCode -eq 3010) { Aviso "o Windows pediu reinicio, mas o backup ja funciona" }
        return $true
    }

    Erro "a instalacao falhou (codigo $($p.ExitCode))"
    Write-Host "    detalhes em: $logMsi"
    return $false
}

# --- o Duplicati existe? Se nao, instala -------------------------------------

function Duplicati-Existe([string]$p) {
    return (Test-Path (CaminhoDe $p 'Duplicati.GUI.TrayIcon.exe')) -or
           (Test-Path (CaminhoDe $p 'Duplicati.Server.exe'))
}

if (-not (Duplicati-Existe $Destino)) {
    Titulo "O Duplicati nao esta instalado neste servidor"
    Write-Host "    Vou instalar agora."

    if (-not (Instalar-Duplicati)) {
        Write-Host ""
        Erro "Nao foi possivel instalar o Duplicati. Nada foi alterado no servidor."
        exit 1
    }

    # Depois de instalar, procura de novo: agora ele existe em algum lugar.
    $achado = Achar-Duplicati
    if ($achado) {
        $Destino = $achado
        Ok "instalado em: $Destino"
    }

    if (-not (Duplicati-Existe $Destino)) {
        Erro "O Duplicati foi instalado mas nao encontrei a pasta dele."
        Write-Host "    Rode o INSTALAR.bat de novo - agora ele deve achar."
        exit 1
    }
}

# Agora sim: $Destino esta definitivo.
$backup = Join-Path $Destino 'backup-original-duplicati'

# --- o que a marca substitui ------------------------------------------------
# nosso = arquivo que NAO existe num Duplicati limpo, foi adicionado por nos.
# Nunca entra no backup (nao ha original) e o -Desfazer simplesmente apaga.

$arquivos = @(
    @{ o = 'oem-custom.css';                                          a = 'oem-custom.css'; nosso = $true }
    @{ o = 'oem-custom.js';                                           a = 'oem-custom.js';  nosso = $true }
    @{ o = 'webroot\index.html';                                      a = 'webroot\index.html' }
    @{ o = 'webroot\login.html';                                      a = 'webroot\login.html' }
    @{ o = 'webroot\signin.html';                                     a = 'webroot\signin.html' }
    @{ o = 'webroot\theme.html';                                      a = 'webroot\theme.html' }
    @{ o = 'webroot\favicon.ico';                                     a = 'webroot\favicon.ico' }
    @{ o = 'webroot\img\logo.png';                                    a = 'webroot\img\logo.png' }
    @{ o = 'webroot\ngax\index.html';                                 a = 'webroot\ngax\index.html' }
    @{ o = 'webroot\ngax\styles\chcom.css';                           a = 'webroot\ngax\styles\chcom.css'; nosso = $true }
    @{ o = 'webroot\ngax\scripts\services\BrandingService.js';        a = 'webroot\ngax\scripts\services\BrandingService.js' }
    @{ o = 'webroot\oem\root\login\oem.css';                          a = 'webroot\oem\root\login\oem.css' }
    @{ o = 'webroot\oem\root\theme\oem.css';                          a = 'webroot\oem\root\theme\oem.css' }
    @{ o = 'webroot\ngclient\assets\duplicati-logo.png';              a = 'webroot\ngclient\assets\duplicati-logo.png' }
    # Fica dentro da pasta do Duplicati porque os atalhos apontam para ele:
    # se o icone morasse na pasta do pacote, sumiria quando ela fosse apagada
    # e os atalhos ficariam com o icone em branco.
    @{ o = 'chcom.ico';                                               a = 'chcom.ico'; nosso = $true }
)

# --- parar o Duplicati ------------------------------------------------------

$estavaRodando = $false
$proc = Get-Process -Name 'Duplicati.GUI.TrayIcon' -ErrorAction SilentlyContinue
if ($proc) {
    $estavaRodando = $true
    Titulo "Parando o Duplicati"
    Stop-Process -InputObject $proc -Force
    try { Wait-Process -InputObject $proc -Timeout 20 -ErrorAction Stop } catch {}
    Ok "parado"
}

$servico = Get-Service -Name '*Duplicati*' -ErrorAction SilentlyContinue |
           Where-Object { $_.Status -eq 'Running' }
if ($servico) {
    Titulo "Parando o servico do Duplicati"
    foreach ($s in $servico) { Stop-Service -InputObject $s -Force; Ok "servico $($s.Name) parado" }
}

<#
    Troca o icone e o nome dos atalhos do Duplicati.

    O icone que aparece na area de trabalho, na barra de tarefas e no menu
    Iniciar nao vem de arquivo nenhum da webroot: vem do ATALHO (.lnk). Por
    isso, mesmo com toda a interface trocada, o cliente continuava vendo o
    boneco azul do Duplicati com o nome "Duplicati" na area de trabalho -- que
    e o primeiro lugar onde ele olha.

    Um .lnk guarda o proprio icone e o proprio nome, entao os dois mudam sem
    tocar no executavel: nada de recompilar, nada de mexer em assinatura
    digital, e o -Desfazer devolve tudo.

    O que este script NAO consegue trocar: o icone que o Duplicati desenha na
    bandeja, ao lado do relogio. Aquele e carregado de dentro do executavel em
    tempo de execucao, e so muda recompilando o programa.
#>
function Ajustar-Atalhos {
    param([switch]$Restaurar)

    $icone = Join-Path $Destino 'chcom.ico'
    $exe = Join-Path $Destino 'Duplicati.GUI.TrayIcon.exe'

    # Onde o Windows guarda atalhos, para todos os usuarios e para o atual
    $locais = @(
        [Environment]::GetFolderPath('CommonDesktopDirectory')
        [Environment]::GetFolderPath('Desktop')
        [Environment]::GetFolderPath('CommonStartMenu')
        [Environment]::GetFolderPath('StartMenu')
        [Environment]::GetFolderPath('CommonStartup')
        [Environment]::GetFolderPath('Startup')
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs"
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
    ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

    $shell = New-Object -ComObject WScript.Shell
    $mexidos = 0

    Titulo $(if ($Restaurar) { "Devolvendo os atalhos ao padrao" } else { "Ajustando os atalhos (icone e nome)" })

    foreach ($local in $locais) {
        $lnks = Get-ChildItem $local -Filter '*.lnk' -Recurse -ErrorAction SilentlyContinue
        foreach ($lnk in $lnks) {
            try {
                $atalho = $shell.CreateShortcut($lnk.FullName)

                # So mexe em atalho que aponta para o Duplicati. Um atalho
                # chamado "Duplicati" que aponte para outra coisa nao e nosso.
                if ($atalho.TargetPath -notlike '*Duplicati.GUI.TrayIcon.exe' -and
                    $atalho.TargetPath -notlike '*Duplicati.Server.exe') { continue }

                if ($Restaurar) {
                    $atalho.IconLocation = "$($atalho.TargetPath), 0"
                    $atalho.Description = 'Duplicati'
                    $atalho.Save()

                    $novoNome = Join-Path $lnk.DirectoryName 'Duplicati.lnk'
                    if ($lnk.Name -like 'CH.Com Backup*' -and -not (Test-Path $novoNome)) {
                        Rename-Item $lnk.FullName $novoNome -Force
                    }
                    Ok "restaurado: $($lnk.Name)"
                }
                else {
                    if (Test-Path $icone) { $atalho.IconLocation = "$icone, 0" }
                    $atalho.Description = 'CH.Com Backup - backup gerenciado pela CH.Com'
                    $atalho.Save()

                    # Renomear e o que tira a palavra "Duplicati" de baixo do
                    # icone na area de trabalho.
                    if ($lnk.BaseName -like '*Duplicati*') {
                        $novoNome = Join-Path $lnk.DirectoryName 'CH.Com Backup.lnk'
                        if (-not (Test-Path $novoNome)) {
                            Rename-Item $lnk.FullName $novoNome -Force
                        } else {
                            Remove-Item $lnk.FullName -Force
                        }
                    }
                    Ok "ajustado: $($lnk.Name)"
                }
                $mexidos++
            }
            catch {
                Aviso "nao consegui ajustar $($lnk.Name): $($_.Exception.Message)"
            }
        }
    }

    if ($mexidos -eq 0) {
        Aviso "nenhum atalho do Duplicati encontrado"
    } else {
        # O Explorer guarda os icones em cache e nao repara na troca sozinho.
        # Sem isso, o icone velho fica na tela ate o proximo logon e parece
        # que nada aconteceu.
        try {
            ie4uinit.exe -show 2>$null
        } catch {
            try { ie4uinit.exe -ClearIconCache 2>$null } catch { }
        }
    }
}

# =============================================================================
#  A PARTIR DAQUI O DUPLICATI ESTA PARADO.
#
#  Tudo o que vem abaixo fica dentro de try/finally, e o finally religa. Esta
#  e a parte mais importante do script inteiro: se algo falhar, se o arquivo
#  estiver em uso, se o operador fechar a janela ou apertar Ctrl+C no meio, o
#  Duplicati TEM que voltar.
#
#  Sem isso, uma interrupcao no meio deixa o servidor do cartorio com o backup
#  DESLIGADO, em silencio, ate alguem reparar. Aconteceu em teste: o script
#  congelou entre parar e religar, e o Duplicati passou horas fora do ar.
#
#  Trocar a marca e cosmetico. Deixar o backup parado nao e.
# =============================================================================

try {

# --- desfazer ---------------------------------------------------------------

if ($Desfazer) {
    Titulo "Removendo a marca CH.Com"

    foreach ($f in $arquivos) {
        $orig = Join-Path $backup $f.a
        $dest = Join-Path $Destino $f.a

        if ($f.nosso) {
            if (Test-Path $dest) { Remove-Item $dest -Force; Ok "removido:   $($f.a)" }
            if (Test-Path $orig) { Remove-Item $orig -Force }
        }
        elseif (Test-Path $orig) {
            Copy-Item $orig $dest -Force
            Ok "restaurado: $($f.a)"
        }
        else {
            Aviso "sem backup de $($f.a) - deixado como esta"
        }
    }

    Ajustar-Atalhos -Restaurar:$true

    Write-Host ""
    Write-Host "  Marca removida. O Duplicati voltou ao visual original." -ForegroundColor Green
    Write-Host "  A configuracao de envio de relatorios NAO foi alterada." -ForegroundColor Yellow
}
else {
    # --- aplicar ------------------------------------------------------------

    Titulo "Aplicando a marca CH.Com"

    if (-not (Test-Path $backup)) { New-Item -ItemType Directory -Path $backup -Force | Out-Null }

    foreach ($f in $arquivos) {
        $origem = Join-Path $pasta "marca\$($f.o)"
        if (-not (Test-Path $origem)) { Aviso "pulado (nao veio no pacote): $($f.o)"; continue }

        $dest = Join-Path $Destino $f.a
        $bkp  = Join-Path $backup $f.a

        # Backup so na primeira vez. Na segunda execucao o arquivo ja e o
        # nosso, e guarda-lo por cima perderia o original para sempre.
        if (-not $f.nosso -and (Test-Path $dest) -and -not (Test-Path $bkp)) {
            $d = Split-Path $bkp -Parent
            if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
            Copy-Item $dest $bkp -Force
        }

        $d = Split-Path $dest -Parent
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
        Copy-Item $origem $dest -Force
        Ok "aplicado: $($f.a)"
    }

    Write-Host ""
    Write-Host "  Marca aplicada. Originais guardados em:" -ForegroundColor Green
    Write-Host "    $backup"

    Ajustar-Atalhos -Restaurar:$false
}

}
finally {
    # --- religar — SEMPRE ---------------------------------------------------
    #
    # Roda mesmo se o bloco acima falhou ou foi interrompido. Cada passo tem o
    # seu proprio try: se religar o servico falhar, ainda tentamos o TrayIcon.
    # Um erro aqui nao pode impedir a outra metade de subir.

    if ($servico) {
        Titulo "Religando o servico"
        foreach ($s in $servico) {
            try { Start-Service -Name $s.Name; Ok "servico $($s.Name) iniciado" }
            catch { Erro "NAO consegui religar o servico $($s.Name): $($_.Exception.Message)" }
        }
    }

    # Liga o Duplicati SEMPRE, tenha ele sido parado por nos ou nao.
    #
    # A versao anterior so religava o que estava ligado antes. Parece
    # cuidadoso, mas produziu o pior resultado possivel num servidor real: o
    # Duplicati estava desligado, o script aplicou tudo, nao ligou nada, e o
    # tecnico ficou com um servidor sem tela de backup nenhuma, achando que a
    # instalacao tinha quebrado o programa.
    #
    # O objetivo aqui nao e "restaurar o estado anterior". E terminar com o
    # backup funcionando. Se o Duplicati estava desligado, provavelmente era
    # justamente isso que precisava ser resolvido.
    Titulo "Ligando o CH.Com Backup"
    try {
        # --webservice-suppress-welcome-page desliga a tela de boas-vindas que o
        # Duplicati mostra no primeiro acesso.
        #
        # Nao e cosmetica. Aquela tela oferece conectar o backup ao console em
        # nuvem da propria Duplicati - um servico de terceiro, pago, que faz o
        # mesmo que o nosso painel. Um funcionario do cartorio clicando ali
        # manda os relatorios do cartorio para fora, e a tela ainda vem com a
        # marca "duplicati", que e justamente o que este instalador tira.
        #
        # Basta uma vez: a opcao grava shown-welcome-page-v1 no banco e vale
        # dali em diante. Vai como argumento comum porque nao e segredo.
        Start-Process (Join-Path $Destino 'Duplicati.GUI.TrayIcon.exe') `
            -ArgumentList '--webservice-suppress-welcome-page=true'
        Ok "iniciado"
    } catch {
        Erro "NAO consegui iniciar o CH.Com Backup: $($_.Exception.Message)"
    }

    # Confere de verdade: o que importa e o servidor estar atendendo, e o
    # operador precisa saber disso em letras claras antes de sair do servidor.
    $voltou = $false
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Seconds 2
        $c = New-Object System.Net.Sockets.TcpClient
        try { $c.Connect('127.0.0.1', $PortaDuplicati); if ($c.Connected) { $voltou = $true } }
        catch { } finally { $c.Close() }
        if ($voltou) { break }
    }

    Write-Host ""
    if ($voltou) {
        Write-Host "  ===============================================================" -ForegroundColor Green
        Write-Host "     BACKUP NO AR" -ForegroundColor Green
        Write-Host "     Abrindo no navegador: http://localhost:$PortaDuplicati" -ForegroundColor Green
        Write-Host "  ===============================================================" -ForegroundColor Green

        # Abre a tela sozinho. Quem instala quer VER funcionando, nao anotar
        # um endereco para digitar depois.
        #
        # Vai por explorer.exe de proposito: este script roda como
        # administrador, e um Start-Process direto abriria o navegador tambem
        # elevado — o Chrome recusa isso quando ja existe uma janela normal
        # aberta, e nada acontece. O explorer.exe repassa a abertura para a
        # sessao normal do usuario, e a janela aparece.
        try {
            Start-Process explorer.exe -ArgumentList "http://localhost:$PortaDuplicati"
        } catch {
            Aviso "nao consegui abrir o navegador; acesse http://localhost:$PortaDuplicati"
        }
    } else {
        Write-Host "  ===============================================================" -ForegroundColor Red
        Write-Host "     ATENCAO: O DUPLICATI NAO SUBIU" -ForegroundColor Red
        Write-Host "     O backup deste servidor esta PARADO neste momento." -ForegroundColor Red
        Write-Host ""
        Write-Host "     Abra manualmente antes de sair daqui:" -ForegroundColor Red
        Write-Host "     $(Join-Path $Destino 'Duplicati.GUI.TrayIcon.exe')" -ForegroundColor Red
        Write-Host "  ===============================================================" -ForegroundColor Red
    }
}

# --- configurar o envio de relatorios ---------------------------------------

if ($Desfazer -or -not $Token) {
    if (-not $Desfazer -and -not $Token) {
        Write-Host ""
        Aviso "Envio de relatorios NAO configurado (voce nao passou -Token)."
        Aviso "Para configurar depois, rode de novo com -Token e -UrlPainel."
    }
    Write-Host ""
    exit 0
}

if (-not $UrlPainel) {
    Erro "Voce passou -Token mas nao -UrlPainel. Informe os dois."
    exit 1
}

Titulo "Configurando o envio de relatorios para o painel"

if ($AceitarCertificadoInvalido) {
    Add-Type @"
using System.Net; using System.Security.Cryptography.X509Certificates;
public class SemChecagem : ICertificatePolicy {
  public bool CheckValidationResult(ServicePoint s, X509Certificate c, WebRequest r, int p) { return true; }
}
"@
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object SemChecagem
}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$urlRelatorio = "$($UrlPainel.TrimEnd('/'))/api/report/$Token"
$base = "http://127.0.0.1:$PortaDuplicati"

if (-not $SenhaDuplicati) {
    $SenhaDuplicati = Pedir-Senha
    if (-not $SenhaDuplicati) {
        Aviso "Senha nao informada. A marca ja foi aplicada; so o envio nao foi configurado."
        Aviso "Rode de novo quando tiver a senha em maos."
        exit 0
    }
}

# Espera o servidor voltar depois do restart.
#
# A checagem é uma conexão TCP na porta, não uma requisição HTTP. O Duplicati
# responde 401 antes do login, e o Invoke-WebRequest trata 401 como erro
# terminante: mesmo dentro de try/catch, a mensagem vermelha vai para a tela.
# Quem está instalando veria um "erro 401 Não Autorizado" no meio de uma
# execução que está indo bem. Se a porta aceita conexão, o servidor subiu —
# é tudo o que precisamos saber aqui.
$noAr = $false
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 2
    $cliente = New-Object System.Net.Sockets.TcpClient
    try {
        $cliente.Connect('127.0.0.1', $PortaDuplicati)
        if ($cliente.Connected) { $noAr = $true }
    } catch { }
    finally { $cliente.Close() }
    if ($noAr) { break }
}
if (-not $noAr) {
    Erro "O Duplicati nao respondeu em $base."
    Erro "Se ele atende em outra porta, use -PortaDuplicati. A marca ja foi aplicada."
    exit 1
}

try {
    $login = Invoke-RestMethod "$base/api/v1/auth/login" -Method Post -TimeoutSec 20 `
             -ContentType 'application/json' -Body (@{ Password = $SenhaDuplicati } | ConvertTo-Json)
    $cab = @{ Authorization = "Bearer $($login.AccessToken)" }
} catch {
    Erro "Senha do Duplicati recusada. A marca ja foi aplicada; so o envio nao foi configurado."
    exit 1
}

# Junta a URL do painel a uma lista existente, sem duplicar e sem substituir.
function Juntar($atual, $nova) {
    $partes = @()
    if ($atual) { $partes = $atual.Split(';') | ForEach-Object { $_.Trim() } | Where-Object { $_ } }
    if ($partes -contains $nova) { return $null }
    return (($partes + $nova) -join ';')
}

# 1. opcao padrao do servidor: vale para todos os backups deste Duplicati
$cfg = Invoke-RestMethod "$base/api/v1/serversettings" -Headers $cab -TimeoutSec 20
$atual = $cfg.'--send-http-json-urls'
$nova = Juntar $atual $urlRelatorio

if ($null -eq $nova) {
    Ok "opcao do servidor ja estava configurada"
} else {
    $corpo = @{ '--send-http-json-urls' = $nova } | ConvertTo-Json
    Invoke-RestMethod "$base/api/v1/serversettings" -Method Patch -Headers $cab `
        -ContentType 'application/json' -Body $corpo -TimeoutSec 20 | Out-Null
    Ok "opcao do servidor gravada"
}

# 2. backups que tem opcao propria
#
# Este passo e o que faz a diferenca. A opcao do BACKUP sobrescreve a do
# servidor -- nao soma. Sem tratar um a um, um cartorio que ja mande
# relatorio para outro sistema continuaria mandando so para la, e o painel
# nunca receberia nada, sem nenhum erro aparecer.
$ajustados = 0
$lista = Invoke-RestMethod "$base/api/v1/backups" -Headers $cab -TimeoutSec 20
foreach ($item in $lista) {
    $bid = $item.Backup.ID
    if (-not $bid) { continue }

    $det = Invoke-RestMethod "$base/api/v1/backup/$bid" -Headers $cab -TimeoutSec 20
    $cfgb = if ($det.data) { $det.data } else { $det }
    $sets = $cfgb.Backup.Settings
    if (-not $sets) { continue }

    $propria = $sets | Where-Object { $_.Name -eq '--send-http-json-urls' -or $_.Name -eq 'send-http-json-urls' }
    if (-not $propria) { continue }   # coberto pela opcao do servidor

    $n = Juntar $propria.Value $urlRelatorio
    if ($null -eq $n) { continue }

    $propria.Value = $n
    Invoke-RestMethod "$base/api/v1/backup/$bid" -Method Put -Headers $cab `
        -ContentType 'application/json' -Body ($cfgb | ConvertTo-Json -Depth 12) -TimeoutSec 30 | Out-Null

    Ok "backup '$($item.Backup.Name)' ajustado (a URL que ja existia foi preservada)"
    $ajustados++
}

Write-Host ""
Write-Host "  Pronto." -ForegroundColor Green
Write-Host "    relatorios vao para: $urlRelatorio"
if ($ajustados -gt 0) {
    Write-Host "    $ajustados backup(s) tinham envio proprio e receberam a URL do painel junto." -ForegroundColor Yellow
}
Write-Host ""
Write-Host "  Vale a partir do PROXIMO backup deste cartorio - nada e enviado"
Write-Host "  retroativamente. Para conferir agora, dispare um backup manual."
Write-Host ""
