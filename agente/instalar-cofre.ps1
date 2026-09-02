<#
================================================================================
  CH.Com Cofre - instalacao

  UM PROGRAMA SO. Copia os arquivos, baixa o rclone, cria os atalhos, poe o
  icone da bandeja para subir com o Windows, e abre o assistente.

  A configuracao - cartorio, destino na AWS, credenciais, chave, teste e
  agendamento - acontece na JANELA do assistente, nao aqui. Quem instala num
  cartorio nao deveria precisar responder pergunta em tela preta.

  USO
      Dois cliques em INSTALAR.bat
================================================================================
#>

[CmdletBinding()]
param(
    # Onde instalar. O padrao e Arquivos de Programas: o Cofre roda como
    # SYSTEM pelo Agendador, e uma pasta na area de trabalho de alguem
    # desaparece no dia em que aquele usuario for removido.
    [string]$Destino = (Join-Path $env:ProgramFiles 'CH.Com Cofre'),
    [switch]$NaoAbrir,

    # Instala o modo GERENTE - a versao que enxerga o parque inteiro na tela
    # "Todos os cartorios". Sem isto, instala o modo cartorio, que e o que vai
    # para os clientes.
    #
    # O padrao e o mais fechado de proposito: errar para o lado de esconder e
    # inofensivo; errar para o outro coloca a lista dos 38 cartorios no balcao
    # de um deles.
    [switch]$Gerente
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$origem = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $origem 'modulos\comum.ps1')

DesligarCliqueQueTrava
Marca
Titulo 'Instalando o CH.Com Cofre'

if (-not (EhAdministrador)) {
    Erro 'este programa precisa ser executado como Administrador.'
    Nota 'Feche e use o INSTALAR.bat, que pede a elevacao sozinho.'
    Write-Host ''; exit 1
}

# ==============================================================================
#  1. Copiar os arquivos
# ==============================================================================
Titulo '1. Copiando os arquivos'

# Instalar por cima de uma instalacao que ja existe nao pode apagar a
# configuracao nem o historico do cartorio.
$preservar = @('cofre.conf', 'rclone.conf', 'estado.json')
$guardados = @{}
foreach ($p in $preservar) {
    $caminho = CaminhoDe $Destino $p
    if (Test-Path $caminho) {
        $guardados[$p] = [System.IO.File]::ReadAllBytes($caminho)
        Nota "guardando $p da instalacao anterior"
    }
}

<#
    RODAR O INSTALADOR DE DENTRO DA PROPRIA INSTALACAO.

    Acontece assim: o Cofre ja esta em C:\Program Files\CH.Com Cofre, alguem
    procura "instalar-cofre.ps1" na maquina, acha o que esta LA DENTRO, e roda.
    Origem e destino viram a mesma pasta.

    O Copy-Item entao tenta copiar cada arquivo em cima de si mesmo e para com

        Nao pode substituir o item ... por ele mesmo

    O instalador morria ali, no primeiro passo, sem criar atalho e sem abrir o
    programa - dando a impressao de que a instalacao inteira falhou, quando na
    verdade ela ja estava feita.

    Comparar os caminhos resolvidos e nao os textos: "C:\Program Files\CH.Com
    Cofre" e "C:\PROGRA~1\CH.Com Cofre" sao a mesma pasta escritos diferente,
    e o nome curto aparece sozinho em varios caminhos do Windows.
#>
function MesmaPasta([string]$a, [string]$b) {
    if (-not $a -or -not $b) { return $false }
    if (-not (Test-Path $a) -or -not (Test-Path $b)) { return $false }
    $ra = (Get-Item $a).FullName.TrimEnd('\')
    $rb = (Get-Item $b).FullName.TrimEnd('\')
    return ($ra -ieq $rb)
}

try {
    if (-not (Test-Path $Destino)) { New-Item -ItemType Directory -Path $Destino -Force | Out-Null }

    if (MesmaPasta $origem $Destino) {
        Ok 'o Cofre ja esta instalado nesta pasta - nada a copiar'
        Nota 'seguindo para os atalhos e o agendamento'
    } else {
        foreach ($item in @(Get-ChildItem $origem -Force)) {
            # Nao copia o que pertence a ESTA maquina de origem nem lixo de
            # execucao: historico e registros sao do servidor, nao do instalador.
            if ($item.Name -in @('historico', 'registros', 'cofre.conf', 'rclone.conf', 'estado.json')) { continue }
            Copy-Item $item.FullName -Destination $Destino -Recurse -Force
        }
        Ok "arquivos copiados para $Destino"
    }

    <#
        O modo fica gravado na instalacao, e nao perguntado na tela.

        Quem instala num cartorio nao pode poder errar isso: uma caixa de
        selecao ali significaria, mais cedo ou mais tarde, um cartorio
        enxergando a situacao dos outros 37.

        Gravado DEPOIS da copia de proposito - a copia sobrescreve a pasta
        inteira, entao um modo.txt escrito antes seria substituido pelo do
        pacote.
    #>
    $modo = if ($Gerente) { 'gerente' } else { 'cartorio' }
    [System.IO.File]::WriteAllText((Join-Path $Destino 'modo.txt'), $modo,
        [System.Text.UTF8Encoding]::new($false))
    if ($Gerente) {
        Ok 'modo GERENTE - esta instalacao enxerga todos os cartorios'
    } else {
        Ok 'modo CARTORIO - esta instalacao enxerga apenas este servidor'
    }

} catch {
    Erro "nao consegui copiar: $($_.Exception.Message)"
    exit 1
}

foreach ($p in $guardados.Keys) {
    [System.IO.File]::WriteAllBytes((CaminhoDe $Destino $p), $guardados[$p])
    Ok "$p da instalacao anterior mantido"
}

# ==============================================================================
#  2. Pasta de dados
#
#  Configuracao, estado e historico NAO ficam em Arquivos de Programas: aquela
#  pasta e somente leitura para quem nao e administrador, e a janela roda como
#  usuario comum. Conferido em teste: gravar la sem elevacao devolve "acesso
#  ao caminho foi negado", e o assistente falharia ao salvar a configuracao.
#
#  As permissoes sao explicitas porque o rclone.conf, que fica aqui, carrega a
#  CHAVE DE CRIPTOGRAFIA - e ele ganha ainda uma restricao propria quando for
#  criado. Usuarios comuns podem LER a pasta (a janela precisa ler o
#  estado.json para mostrar a situacao), mas nao escrever.
# ==============================================================================
Titulo '2. Pasta de dados'
$dados = CaminhoDe $env:ProgramData 'CH.Com Cofre'
try {
    if (-not (Test-Path $dados)) { New-Item -ItemType Directory -Path $dados -Force | Out-Null }

    $acl = Get-Acl $dados
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($r in @($acl.Access)) { [void]$acl.RemoveAccessRule($r) }

    foreach ($quem in @('BUILTIN\Administrators', 'NT AUTHORITY\SYSTEM')) {
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            $quem, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
    }
    # Usuarios: leem, para a janela mostrar a situacao sem pedir elevacao.
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        'BUILTIN\Users', 'ReadAndExecute', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))

    Set-Acl -Path $dados -AclObject $acl
    Ok "$dados"
    Nota 'administradores e sistema escrevem; usuarios so leem'

    # Migra a configuracao de uma instalacao antiga que gravava na pasta do
    # programa - senao o cartorio perderia o destino e a chave na atualizacao.
    foreach ($p in $preservar) {
        $antigo = CaminhoDe $Destino $p
        $novo = CaminhoDe $dados $p
        if ((Test-Path $antigo) -and -not (Test-Path $novo)) {
            Move-Item $antigo $novo -Force
            Ok "$p movido para a pasta de dados"
        }
    }
} catch {
    Erro "nao consegui preparar a pasta de dados: $($_.Exception.Message)"
    exit 1
}

# ==============================================================================
#  2. rclone
# ==============================================================================
Titulo '3. Ferramenta de envio'
$rclone = CaminhoDe $Destino 'rclone.exe'

if (Test-Path $rclone) {
    Ok 'rclone ja presente'
} else {
    Passo 'baixando o rclone do site oficial (cerca de 20 MB)...'
    $zip = CaminhoDe $env:TEMP 'rclone-cofre.zip'
    $tmp = CaminhoDe $env:TEMP 'rclone-cofre'
    try {
        # TLS 1.2 explicito: o padrao do PowerShell 5.1 e antigo demais e o
        # site recusa a conexao com um erro que nao explica nada.
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri 'https://downloads.rclone.org/rclone-current-windows-amd64.zip' `
            -OutFile $zip -UseBasicParsing -TimeoutSec 300
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
        Expand-Archive -Path $zip -DestinationPath $tmp -Force
        $achado = @(Get-ChildItem $tmp -Filter 'rclone.exe' -Recurse -File)
        if ($achado.Count -eq 0) { throw 'o pacote baixado nao tem rclone.exe dentro' }
        Copy-Item $achado[0].FullName $rclone -Force
        Ok 'rclone instalado'
    } catch {
        Erro "nao consegui baixar o rclone: $($_.Exception.Message)"
        Nota 'Sem internet liberada? Baixe em https://rclone.org/downloads/'
        Nota "e coloque o rclone.exe em: $Destino"
        exit 1
    } finally {
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ==============================================================================
#  3. Atalhos
# ==============================================================================
Titulo '4. Atalhos'
$icone = CaminhoDe (CaminhoDe $Destino 'marca') 'chcom.ico'
$telaPrincipal = CaminhoDe (CaminhoDe $Destino 'interface') 'cofre-ui.ps1'

function CriarAtalho([string]$caminho, [string]$alvo, [string]$argumentos, [string]$descricao) {
    $shell = New-Object -ComObject WScript.Shell
    $a = $shell.CreateShortcut($caminho)
    $a.TargetPath = $alvo
    $a.Arguments = $argumentos
    $a.WorkingDirectory = $Destino
    <#
        O ",0" nao e enfeite.

        IconLocation espera "caminho,indice". So o caminho funciona em alguns
        Windows e e ignorado em outros - e ai o atalho sai com o icone
        generico do PowerShell, que e o que o cliente ve na area de trabalho
        dele.
    #>
    $a.IconLocation = "$icone,0"
    $a.Description = $descricao
    $a.Save()
}

$argsJanela = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $telaPrincipal + '"'

try {
    CriarAtalho (CaminhoDe ([Environment]::GetFolderPath('CommonDesktopDirectory')) 'CH.Com Cofre.lnk') `
        'powershell.exe' $argsJanela 'CH.Com Cofre - copia externa para desastre'
    Ok 'atalho na area de trabalho'

    $menu = CaminhoDe ([Environment]::GetFolderPath('CommonPrograms')) 'CH.Com'
    if (-not (Test-Path $menu)) { New-Item -ItemType Directory -Path $menu -Force | Out-Null }
    CriarAtalho (CaminhoDe $menu 'CH.Com Cofre.lnk') 'powershell.exe' $argsJanela `
        'CH.Com Cofre - copia externa para desastre'
    Ok 'atalho no menu Iniciar'
} catch {
    Aviso "nao consegui criar os atalhos: $($_.Exception.Message)"
}

# ==============================================================================
#  4. Icone da bandeja no boot
#
#  Vai em HKLM, e nao em HKCU: o icone precisa aparecer para quem quer que
#  faca login no servidor, e nao so para o tecnico que instalou.
# ==============================================================================
Titulo '5. Icone ao lado do relogio'
try {
    $chave = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    $comando = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' +
               (CaminhoDe $Destino 'bandeja.ps1') + '"'
    Set-ItemProperty -Path $chave -Name 'CH.Com Cofre' -Value $comando -Force
    Ok 'o icone vai subir junto com o Windows'
} catch {
    Aviso "nao consegui registrar o icone no boot: $($_.Exception.Message)"
}

# ==============================================================================
#  5. Desinstalacao registrada
#
#  Aparece em Aplicativos e Recursos, como qualquer programa. Um sistema que
#  so pode ser removido apagando pasta a mao nao e um sistema instalado.
# ==============================================================================
Titulo '6. Registro do programa'
try {
    $reg = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\CHComCofre'
    if (-not (Test-Path $reg)) { New-Item -Path $reg -Force | Out-Null }
    Set-ItemProperty -Path $reg -Name 'DisplayName'     -Value 'CH.Com Cofre'
    Set-ItemProperty -Path $reg -Name 'DisplayVersion'  -Value '1.0'
    Set-ItemProperty -Path $reg -Name 'Publisher'       -Value 'CH.Com Solucoes em Tecnologia'
    Set-ItemProperty -Path $reg -Name 'DisplayIcon'     -Value $icone
    Set-ItemProperty -Path $reg -Name 'InstallLocation' -Value $Destino
    Set-ItemProperty -Path $reg -Name 'NoModify'        -Value 1 -Type DWord
    Set-ItemProperty -Path $reg -Name 'UninstallString' -Value (
        'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' +
        (CaminhoDe $Destino 'desinstalar-cofre.ps1') + '"')
    Ok 'registrado em Aplicativos e Recursos'
} catch {
    Aviso "nao consegui registrar: $($_.Exception.Message)"
}

# ==============================================================================
#  Pronto
# ==============================================================================
Write-Host ''
Caixa @('CH.Com COFRE INSTALADO',
        '',
        $Destino,
        '',
        'A configuracao continua na janela que vai abrir.') 'Green'

if (-not $NaoAbrir) {
    Passo 'abrindo o CH.Com Cofre...'
    Start-Process powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass',
        '-WindowStyle','Hidden','-File', (Aspas $telaPrincipal))
    Start-Sleep -Seconds 2
    Start-Process powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass',
        '-WindowStyle','Hidden','-File', (Aspas (CaminhoDe $Destino 'bandeja.ps1')))
}
Write-Host ''
