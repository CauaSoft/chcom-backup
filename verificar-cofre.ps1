<#
================================================================================
  CH.Com Cofre - auditoria do projeto

  Roda ANTES de empacotar. Confere o que da para conferir por maquina, em vez
  de confiar na memoria de quem escreveu.

  A checagem que mais paga: FUNCAO CHAMADA E NUNCA DEFINIDA. E o defeito que
  o parser nao pega, que so aparece quando alguem clica no lugar certo, e que
  num servidor de cartorio aparece as 3 da manha.
================================================================================
#>

[CmdletBinding()]
param([string]$Raiz = 'C:\dev\chcom-cofre')

$ErrorActionPreference = 'Stop'
$problemas = @()
$avisos = @()

function T($t) { Write-Host ''; Write-Host "  $t" -ForegroundColor Cyan }
function Ok($t) { Write-Host "    [OK] $t" -ForegroundColor Green }
function Falha($t) { $script:problemas += $t; Write-Host "    [X ] $t" -ForegroundColor Red }
function Aviso($t) { $script:avisos += $t; Write-Host "    [! ] $t" -ForegroundColor Yellow }
function Nota($t) { Write-Host "         $t" -ForegroundColor DarkGray }

# -notlike com curinga em vez de regex.
#
# Barra invertida em regex escrito por script tem o habito de se perder pelo
# caminho - ja aconteceu duas vezes neste projeto, e uma delas o padrao
# continuou CASANDO e devolvendo vazio, o que e pior que quebrar.
$ps1 = @(Get-ChildItem $Raiz -Filter *.ps1 -Recurse -File |
         Where-Object { $_.FullName -notlike '*\historico\*' -and
                        $_.FullName -notlike '*\registros\*' })
# --- 1. sintaxe ---------------------------------------------------------------
T '1. Sintaxe'
$comErro = 0
foreach ($f in $ps1) {
    $erros = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$erros)
    if ($erros) {
        $comErro++
        Falha "$($f.Name) linha $($erros[0].Extent.StartLineNumber): $($erros[0].Message)"
    }
}
if ($comErro -eq 0) { Ok "$($ps1.Count) script(s) sem erro de sintaxe" }

# --- 2. acento sem BOM --------------------------------------------------------
T '2. Acento em script sem BOM'
# PowerShell 5.1 le .ps1 como ANSI quando nao ha BOM: acento vira lixo na tela
# do servidor. A regra do projeto e ASCII puro, ou BOM.
$ruins = 0
foreach ($f in $ps1) {
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    $temBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $temAcento = $false
    foreach ($b in $bytes) { if ($b -gt 127) { $temAcento = $true; break } }
    if ($temAcento -and -not $temBom) { $ruins++; Falha "$($f.Name) tem acento e nao tem BOM" }
}
if ($ruins -eq 0) { Ok 'todo script e ASCII puro ou tem BOM' }

# --- 3. funcao chamada e nunca definida ---------------------------------------
T '3. Funcoes chamadas que nao existem'
$definidas = @{}
$chamadas = @{}
foreach ($f in $ps1) {
    $tokens = $null; $erros = $null
    $arvore = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$erros)

    foreach ($d in $arvore.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        $definidas[$d.Name.ToLower()] = $f.Name
    }
    foreach ($c in $arvore.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)) {
        $nome = $c.GetCommandName()
        if ($nome) { $chamadas[$nome.ToLower()] = $f.Name }
    }
}

# Nomes que existem fora do projeto: cmdlets, executaveis e palavras da
# linguagem. Sem esta filtragem a lista viria cheia de Get-Item e afins.
<#
    O que existe fora do projeto: cmdlets, executaveis e palavras da
    linguagem. Sem esta filtragem a lista viria cheia de Get-Item.

    E ha um segundo grupo, que a primeira versao acusou como erro: cmdlets de
    modulos que NAO ESTAO INSTALADOS na maquina onde a auditoria roda.

    Get-VM, Export-VM e Compare-VM vem do modulo Hyper-V. Get-WindowsFeature
    vem do ServerManager, que so existe em Windows Server. Numa maquina de
    desenvolvimento sem Hyper-V, Get-Command nao acha nenhum deles - e o
    verificador dizia "funcao inexistente" para o codigo mais correto do
    projeto.

    Marcar isso como falha ensinaria a ignorar a checagem inteira, que e
    justamente a que pega o defeito de verdade. Entao eles entram na lista de
    conhecidos, com o modulo anotado.
#>
$conhecidos = @{}
# Programas entram na lista COM e SEM a extensao.
#
# O Get-Command devolve aplicacoes com o nome completo - "Robocopy.exe" - e o
# codigo as chama sem extensao: "robocopy origem destino". Sem guardar as duas
# formas, o verificador acusava "funcao inexistente: robocopy" para uma
# chamada perfeitamente correta a um programa que vem no Windows.
foreach ($c in @(Get-Command -CommandType Cmdlet,Function,Alias,Application -ErrorAction SilentlyContinue)) {
    $n = $c.Name.ToLower()
    $conhecidos[$n] = $true
    if ($n -match '\.(exe|com|bat|cmd)$') {
        $conhecidos[($n -replace '\.(exe|com|bat|cmd)$', '')] = $true
    }
}
foreach ($p in @('if','else','foreach','while','switch','try','param','return','throw')) { $conhecidos[$p] = $true }

# Cmdlets de modulos que podem faltar na maquina do desenvolvedor, mas
# existem no servidor onde o Cofre roda.
$deModulosOpcionais = @(
    'get-vm','new-vm','export-vm','compare-vm','import-vm','get-vmharddiskdrive',
    'get-vmswitch','new-vmswitch','set-vmmemory','set-vmprocessor','set-vm',
    'get-vmintegrationservice','get-vmcheckpoint','start-vm','stop-vm',
    'get-windowsfeature','install-windowsfeature',
    'mount-diskimage','dismount-diskimage'
)
foreach ($p in $deModulosOpcionais) { $conhecidos[$p] = $true }
$faltando = @()
foreach ($nome in $chamadas.Keys) {
    if ($definidas.ContainsKey($nome)) { continue }
    if ($conhecidos.ContainsKey($nome)) { continue }

    <#
        Nome qualificado pelo modulo.

        O banco de provas troca Start-Process e New-Object por dubles, e
        precisa chamar os originais - o que so da para fazer escrevendo
        "Microsoft.PowerShell.Management\Start-Process". O verificador nao
        reconhecia essa forma e acusava funcao inexistente para o codigo que
        estava certo. Acusar o que esta certo ensina a ignorar o verificador.
    #>
    $semModulo = $nome
    $barra = [string][char]92
    if ($nome.Contains($barra)) { $semModulo = $nome.Substring($nome.LastIndexOf($barra) + 1) }
    if ($definidas.ContainsKey($semModulo)) { continue }
    if ($conhecidos.ContainsKey($semModulo)) { continue }

    $faltando += "$nome (chamada em $($chamadas[$nome]))"
}
if ($faltando.Count -eq 0) { Ok "$($definidas.Count) funcao(oes) definidas, todas as chamadas resolvem" }
else { foreach ($x in $faltando) { Falha "funcao inexistente: $x" } }

# --- 4. pecas obrigatorias ----------------------------------------------------
T '4. Pecas do sistema'
<#
    A auditoria serve para DUAS estruturas, e por isso descobre onde o
    agente esta.

    No projeto:   C:\dev\chcom-cofre\agente\cofre.ps1
    No pacote:    CH.Com-Cofre\cofre.ps1      (sem a subpasta agente)

    Sem isso, verificar o pacote acusava 20 pecas faltando - todas presentes.
    Um verificador que reprova o que esta certo ensina a ignorar verificador.
#>
$prefixo = if (Test-Path (Join-Path $Raiz 'agente\cofre.ps1')) { 'agente\' } else { '' }
if ($prefixo) { Nota 'estrutura do projeto (com a pasta agente)' }
else          { Nota 'estrutura do pacote (arquivos na raiz)' }

$obrigatorios = [ordered]@{
    'cofre.ps1'                     = 'motor'
    'diagnostico-cofre.ps1'         = 'diagnostico'
    'instalar-cofre.ps1'            = 'instalador'
    'restaurar-cofre.ps1'           = 'restauracao'
    'desinstalar-cofre.ps1'         = 'desinstalacao'
    'bandeja.ps1'                   = 'icone ao lado do relogio'
    'modulos\comum.ps1'             = 'tela e registro'
    'modulos\descobrir.ps1'         = 'inventario'
    'modulos\planejar.ps1'          = 'decisao automatica'
    'modulos\exportar-vm.ps1'       = 'export de VM'
    'modulos\imagem-servidor.ps1'   = 'imagem de servidor fisico'
    'modulos\bancos.ps1'            = 'Firebird e SQL Server'
    'modulos\pastas.ps1'            = 'discos e pastas, com copia de sombra'
    'modulos\validar.ps1'           = 'validacao e manifesto'
    'modulos\enviar.ps1'            = 'cripto e envio'
    'modulos\configurar.ps1'        = 'configuracao e chave'
    'modulos\reportar.ps1'          = 'envio ao painel'
    'interface\cofre-ui.ps1'        = 'interface'
    'interface\janela.xaml'         = 'layout'
    'interface\assistente.ps1'      = 'assistente de configuracao'
    'interface\assistente.xaml'     = 'layout do assistente'
    'interface\componentes.ps1'     = 'pecas visuais'
    'interface\telas.ps1'           = 'telas'
    'marca\chcom.ico'               = 'icone'
    'marca\logo-256.png'            = 'logo'
}
$faltam = 0
foreach ($k in $obrigatorios.Keys) {
    $caminho = Join-Path $Raiz ($prefixo + $k)
    if (-not (Test-Path $caminho)) {
        $faltam++
        Falha "falta: $prefixo$k  ($($obrigatorios[$k]))"
    }
}
if ($faltam -eq 0) { Ok "$($obrigatorios.Count) peca(s) no lugar" }

# --- 5. os .bat apontam para arquivos que existem -----------------------------
T '5. Atalhos .bat'
$bats = @(Get-ChildItem $Raiz -Filter *.bat -Recurse -File)
<#
    Confere linha a linha, nao no texto inteiro.

    A primeira versao procurava "%~dp0" e o ".ps1" seguinte no arquivo todo.
    Mas o .bat tem

        cd /d "%~dp0"
        powershell ... -File "%~dp0interface\cofre-ui.ps1"

    e o primeiro "%~dp0" e o do cd - o ".ps1" mais proximo dele esta na LINHA
    SEGUINTE. O resultado era um "caminho" com quebra de linha e aspas dentro,
    que fez o Test-Path reclamar de caracteres invalidos.

    Uma linha por vez elimina o problema na raiz.
#>
$quebrados = 0
foreach ($b in $bats) {
    foreach ($linha in @(Get-Content $b.FullName)) {
        $i = $linha.IndexOf('%~dp0')
        if ($i -lt 0) { continue }
        $j = $linha.IndexOf('.ps1', $i)
        if ($j -lt 0) { continue }
        $alvoRel = $linha.Substring($i + 5, ($j + 4) - ($i + 5))
        $alvo = Join-Path $b.DirectoryName $alvoRel
        if (-not (Test-Path $alvo)) {
            $quebrados++
            Falha "$($b.Name) chama $alvoRel, que nao existe"
        }
    }
}
if ($quebrados -eq 0) { Ok "$($bats.Count) atalho(s) com destino valido" }

# --- 6. nenhum segredo no projeto ---------------------------------------------
T '6. Segredos'
$suspeitos = @(Get-ChildItem $Raiz -Recurse -File -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -in @('rclone.conf','cofre.conf','credenciais.txt','chave.txt') })
if ($suspeitos.Count -gt 0) {
    foreach ($s in $suspeitos) { Aviso "arquivo de configuracao no projeto: $($s.Name) - nao pode ir para o repositorio" }
} else { Ok 'nenhum arquivo de configuracao ou chave no projeto' }

$comSegredo = @()
foreach ($f in $ps1) {
    $t = Get-Content $f.FullName -Raw
    if ($t -match 'AKIA[0-9A-Z]{16}') { $comSegredo += "$($f.Name): parece ter chave da AWS" }
}
if ($comSegredo.Count -gt 0) { foreach ($x in $comSegredo) { Falha $x } }
else { Ok 'nenhuma credencial escrita dentro do codigo' }

# --- veredito -----------------------------------------------------------------
Write-Host ''
if ($problemas.Count -eq 0 -and $avisos.Count -eq 0) {
    Write-Host '  ============================================================' -ForegroundColor Green
    Write-Host '    PROJETO VERIFICADO - nada a corrigir' -ForegroundColor Green
    Write-Host '  ============================================================' -ForegroundColor Green
} else {
    Write-Host "  $($problemas.Count) problema(s), $($avisos.Count) aviso(s)" -ForegroundColor $(if ($problemas.Count) { 'Red' } else { 'Yellow' })
}
Write-Host ''
exit $problemas.Count
