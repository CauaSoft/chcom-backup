# =============================================================================
#  CH.Com Backup - diagnostico do servidor
#
#  Existe para acabar com o vai e volta de "nao abriu" / "o que aparece?".
#  Roda, tira print, manda. Tambem grava um .txt ao lado, caso seja mais
#  facil enviar o arquivo.
#
#  COMO ESTA TELA E ORGANIZADA, E POR QUE
#
#  O VEREDITO VEM PRIMEIRO. A versao anterior despejava oito secoes e so no
#  fim dizia o que fazer - quem estava num cartorio com o backup parado tinha
#  de rolar a tela inteira ate achar a resposta. Agora a primeira coisa na
#  tela e o que esta errado e o que fazer; os detalhes ficam abaixo, para
#  quem precisar deles ou para mandar para o suporte.
#
#  E ele OFERECE RESOLVER. Um diagnostico que so aponta o problema deixa o
#  tecnico abrindo outro programa; se o que falta e ligar o backup, ele liga.
# =============================================================================

$ErrorActionPreference = 'SilentlyContinue'

# O resultado vai para a Area de Trabalho, nao para a pasta do script: a pasta
# do script e a que se leva de cartorio em cartorio, e o resultado de um
# servidor acabava viajando junto para o proximo - onde alguem podia ler como
# se fosse de la.
$mesa = [Environment]::GetFolderPath('Desktop')
$saida = if ($mesa -and (Test-Path $mesa)) {
    Join-Path $mesa "diagnostico-$env:COMPUTERNAME.txt"
} else {
    Join-Path $PSScriptRoot 'diagnostico-resultado.txt'
}

# O texto do arquivo sai sem cor; a cor e so da tela.
$script:linhas = @()

function Reg($t) { $script:linhas += $t }
function Linha($t, $cor = 'Gray') { Reg $t; Write-Host $t -ForegroundColor $cor }
function Secao($t) {
    Reg ''; Reg "-- $t " + ('-' * [Math]::Max(0, 60 - $t.Length))
    Write-Host ''
    Write-Host "  $t " -ForegroundColor DarkCyan -NoNewline
    Write-Host ('-' * [Math]::Max(0, 58 - $t.Length)) -ForegroundColor DarkGray
}
function Item($estado, $t) {
    # [OK] verde, [!] amarelo, [X] vermelho - a marca ja diz sozinha, a cor
    # so reforca: em console preto e branco, ou impresso, continua legivel.
    $marca = switch ($estado) { 'ok' { '[OK]' } 'aviso' { '[! ]' } 'erro' { '[X ]' } default { '    ' } }
    $cor = switch ($estado) { 'ok' { 'Green' } 'aviso' { 'Yellow' } 'erro' { 'Red' } default { 'Gray' } }
    Reg "    $marca $t"
    Write-Host "    $marca " -ForegroundColor $cor -NoNewline
    Write-Host $t -ForegroundColor Gray
}
function Detalhe($t) { Reg "         $t"; Write-Host "         $t" -ForegroundColor DarkGray }

# Desliga o modo de selecao do console: um clique dentro da janela congela o
# programa ate alguem apertar Esc, e o titulo passa a comecar com "Selecionar".
# Como esta tela faz uma pergunta no fim, isso pareceria travamento.
function DesligarCliqueQueTrava {
    try {
        if (-not ('ModoConsole' -as [type])) {
            Add-Type -Namespace '' -Name 'ModoConsole' -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)]
public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
'@
        }
        $h = [ModoConsole]::GetStdHandle(-10)
        $modo = 0
        if ([ModoConsole]::GetConsoleMode($h, [ref]$modo)) {
            [void][ModoConsole]::SetConsoleMode($h, ($modo -band (-bnot 0x40)) -bor 0x80)
        }
    } catch { }
}
DesligarCliqueQueTrava

# =============================================================================
#  LEVANTAMENTO - junta tudo antes de imprimir, para o veredito poder vir
#  primeiro. Imprimir enquanto apura obriga a conclusao a ficar no fim.
# =============================================================================


# Monta um caminho SEM validar a unidade.
#
# O Join-Path do PowerShell confere se a unidade existe e LANCA erro quando
# nao existe - num servidor sem disco D:, testar "D:\Duplicati 2" derrubava
# o instalador inteiro antes de ele achar o Duplicati em C:. Concatenar nao
# valida nada, que e o que se quer numa lista de lugares POSSIVEIS.
function CaminhoDe([string]$pasta, [string]$arquivo) {
    return ($pasta.TrimEnd('\') + '\' + $arquivo)
}

# --- onde esta instalado -----------------------------------------------------
$pastas = @()
foreach ($n in @('Duplicati.GUI.TrayIcon', 'Duplicati.Server', 'Duplicati.WindowsService')) {
    foreach ($p in (Get-Process -Name $n)) { if ($p.Path) { $pastas += Split-Path $p.Path -Parent } }
}
foreach ($c in @("$env:ProgramFiles\Duplicati 2", "${env:ProgramFiles(x86)}\Duplicati 2",
                 "$env:LOCALAPPDATA\Programs\Duplicati 2", 'C:\Duplicati 2', 'D:\Duplicati 2')) {
    if (Test-Path (CaminhoDe $c 'Duplicati.GUI.TrayIcon.exe')) { $pastas += $c }
}
# O @() e obrigatorio: com um unico resultado o pipeline devolve uma STRING, e
# $pastas[0] passaria a valer "C". O diagnostico entao reportaria [X] para
# arquivos que estao la, mandando o tecnico procurar problema onde nao ha.
$pastas = @($pastas | Where-Object { $_ } | Select-Object -Unique)
$pasta = if ($pastas.Count -gt 0) { $pastas[0] } else { $null }
$versao = if ($pasta) { (Get-Item (Join-Path $pasta 'Duplicati.GUI.TrayIcon.exe')).VersionInfo.FileVersion } else { $null }

# --- esta rodando? -----------------------------------------------------------
$procs = @(Get-Process -Name 'Duplicati*')
<#
    A tela responde - e em QUANTAS portas?

    O icone da bandeja sobe o servidor com a lista
    8200,8300,8400,8500,8600,8700,8800,8900,8989 e fica com a primeira livre.
    Entao, se um programa antigo nao morreu direito, o novo sobe na 8300 sem
    avisar e ficam DOIS rodando ao mesmo tempo, cada um fazendo o backup da
    mesma origem para o mesmo destino.

    Isto parava na primeira porta que respondesse (break), e por isso nunca
    veria o segundo. Agora varre a lista inteira, porque a coisa util a
    descobrir nao e "responde?" e sim "responde mais de uma vez?".
#>
$PORTAS_POSSIVEIS = @(8200, 8300, 8400, 8500, 8600, 8700, 8800, 8900, 8989)
$portasVivas = @()
foreach ($porta in $PORTAS_POSSIVEIS) {
    try { $c = New-Object Net.Sockets.TcpClient; $c.Connect('127.0.0.1', $porta); $c.Close(); $portasVivas += $porta }
    catch { }
}
$portaViva = if ($portasVivas.Count -gt 0) { $portasVivas[0] } else { $null }

# --- a marca esta aplicada? --------------------------------------------------
$marcaArquivos = @('oem-custom.css', 'oem-custom.js', 'chcom.ico')
$marcaFaltando = @()
if ($pasta) {
    foreach ($f in $marcaArquivos) {
        if (-not (Test-Path (Join-Path $pasta $f))) { $marcaFaltando += $f }
    }
}

# --- caiu ou foi desligado? --------------------------------------------------
#
# O Windows registra o fim anormal de um processo no log de Aplicativo. E onde
# a resposta esta quando o programa cai duro: nessa hora ele nao consegue
# registrar a propria morte no proprio log.
$quedas = @()
try {
    $quedas = @(Get-WinEvent -FilterHashtable @{
            LogName = 'Application'; StartTime = (Get-Date).AddDays(-3); Id = 1000, 1026
        } -ErrorAction SilentlyContinue | Where-Object { $_.Message -match 'Duplicati' })
} catch { }

# --- quando o backup rodou de verdade? ---------------------------------------
#
# Ate aqui tudo fala do PROGRAMA. O que importa para o cartorio e o BACKUP.
# A data vem da alteracao do banco de cada trabalho, que o Duplicati grava ao
# fim de cada execucao: da para ler sem senha e com o programa desligado, que
# e justamente a situacao em que se roda um diagnostico.
$trabalhos = @()
foreach ($pd in @("$env:LOCALAPPDATA\Duplicati", "$env:APPDATA\Duplicati",
                  'C:\Windows\System32\config\systemprofile\AppData\Local\Duplicati')) {
    if (-not (Test-Path $pd)) { continue }
    foreach ($b in (Get-ChildItem $pd -Filter *.sqlite | Where-Object { $_.Name -notlike 'Duplicati-server*' })) {
        $trabalhos += [PSCustomObject]@{
            Nome  = $b.Name
            Data  = $b.LastWriteTime
            Horas = [math]::Round(((Get-Date) - $b.LastWriteTime).TotalHours, 1)
            MB    = [math]::Round($b.Length / 1MB, 0)
        }
    }
}
$trabalhos = @($trabalhos | Sort-Object Data -Descending)
$maisAtrasado = if ($trabalhos.Count -gt 0) { ($trabalhos | Select-Object -Last 1).Horas } else { $null }

# =============================================================================
#  VEREDITO
# =============================================================================

Write-Host ''
Write-Host '  CH.Com Backup - diagnostico' -ForegroundColor Cyan
Write-Host "  $env:COMPUTERNAME  -  $(Get-Date -Format 'dd/MM/yyyy HH:mm')" -ForegroundColor DarkGray
Reg "  CH.Com Backup - diagnostico"
Reg "  $env:COMPUTERNAME  -  $(Get-Date -Format 'dd/MM/yyyy HH:mm')"

$gravidade = 'ok'
$titulo = 'ESTA TUDO CERTO'
$oQueFazer = @()

if (-not $pasta) {
    $gravidade = 'erro'
    $titulo = 'O PROGRAMA NAO ESTA INSTALADO'
    $oQueFazer = @('Rode o INSTALAR.bat desta mesma pasta. Ele baixa e instala.')
} elseif ($procs.Count -eq 0 -or -not $portaViva) {
    $gravidade = 'erro'
    $titulo = 'O BACKUP ESTA PARADO - O CARTORIO NAO ESTA SENDO COPIADO'
    $oQueFazer = @(
        'Ligue o programa agora (este diagnostico pode ligar - veja o fim da tela).',
        'Depois abra http://localhost:8200 e confira se o backup aparece.'
    )
    if ($quedas.Count -gt 0) {
        $oQueFazer += 'O Windows registrou que o programa CAIU sozinho (secao abaixo).'
        $oQueFazer += 'Se cair de novo, mande esta tela para o suporte.'
    }
} elseif ($maisAtrasado -ne $null -and $maisAtrasado -gt 48) {
    $gravidade = 'erro'
    $titulo = 'O PROGRAMA ESTA NO AR, MAS O BACKUP NAO RODA HA MAIS DE 2 DIAS'
    $oQueFazer = @(
        'Abra http://localhost:8200 e veja o erro do backup.',
        'Se disser "s3-aws is not supported", rode o CORRIGIR-S3.bat.'
    )
} elseif ($maisAtrasado -ne $null -and $maisAtrasado -gt 26) {
    $gravidade = 'aviso'
    $titulo = 'O BACKUP ESTA ATRASADO'
    $oQueFazer = @('Abra http://localhost:8200 e confira o agendamento e o ultimo erro.')
} elseif ($marcaFaltando.Count -gt 0) {
    $gravidade = 'aviso'
    $titulo = 'FUNCIONANDO, MAS SEM A MARCA CH.Com'
    $oQueFazer = @('Rode o INSTALAR.bat para aplicar a marca.')
} elseif ($quedas.Count -gt 0) {
    # Esta no ar AGORA, mas caiu sozinho nos ultimos dias. Nao e "tudo certo":
    # e um programa que ja abandonou o posto e vai abandonar de novo, e nesse
    # meio-tempo o cartorio fica sem copia sem ninguem perceber.
    $gravidade = 'aviso'
    $titulo = 'FUNCIONANDO AGORA, MAS O PROGRAMA JA CAIU SOZINHO'
    $oQueFazer = @(
        "O Windows registrou $($quedas.Count) queda(s) nos ultimos 3 dias (secao abaixo).",
        'O backup fica parado entre a queda e alguem perceber.',
        'Mande esta tela para o suporte da CH.Com.'
    )
} else {
    $oQueFazer = @("Backup rodando e em dia. Tela em http://localhost:$portaViva")
}

$corV = switch ($gravidade) { 'ok' { 'Green' } 'aviso' { 'Yellow' } default { 'Red' } }
$borda = '  ' + ('=' * 64)
Write-Host ''
Write-Host $borda -ForegroundColor $corV
Write-Host "   $titulo" -ForegroundColor $corV
Write-Host $borda -ForegroundColor $corV
Reg ''; Reg $borda; Reg "   $titulo"; Reg $borda
Write-Host ''
Reg ''
foreach ($o in $oQueFazer) {
    Write-Host "   -> $o" -ForegroundColor White
    Reg "   -> $o"
}

# =============================================================================
#  DETALHES
# =============================================================================

Secao 'Programa'
if ($pasta) {
    Item 'ok' "instalado em $pasta"
    Detalhe "versao $versao"
} else {
    Item 'erro' 'nao encontrado em nenhum lugar conhecido'
}

if ($procs.Count -gt 0) {
    Item 'ok' "rodando ($($procs.Count) processo(s))"
    foreach ($p in $procs) { Detalhe "$($p.ProcessName) - desde $($p.StartTime)" }
} else {
    Item 'erro' 'DESLIGADO - nenhum processo rodando'
}

if ($portasVivas.Count -eq 0) {
    Item 'erro' 'a tela nao responde em nenhuma porta'
} elseif ($portasVivas.Count -eq 1) {
    Item 'ok' "tela responde em http://localhost:$portaViva"
    if ($portaViva -ne 8200) {
        Detalhe "atencao: a porta normal e a 8200, e este servidor esta na $portaViva."
        Detalhe 'As outras ferramentas procuram na 8200. Reinicie o servidor para'
        Detalhe 'ele voltar para a porta normal.'
    }
} else {
    # Duas telas respondendo = dois programas rodando. Os dois fazem backup da
    # mesma origem para o mesmo destino, ao mesmo tempo. E o destino na nuvem
    # nao foi feito para dois donos: um sobrescreve o indice do outro.
    Item 'erro' "HA $($portasVivas.Count) PROGRAMAS RODANDO AO MESMO TEMPO"
    Detalhe "portas respondendo: $($portasVivas -join ', ')"
    Detalhe 'Isso acontece quando um programa antigo nao morreu e o novo subiu'
    Detalhe 'numa porta livre. Os dois fazem o mesmo backup e brigam pelo'
    Detalhe 'destino na nuvem.'
    Detalhe 'CONSERTO: reinicie este servidor. Depois rode este diagnostico de'
    Detalhe 'novo e confira que sobrou so a 8200.'
}

Secao 'Marca CH.Com'
if (-not $pasta) {
    Item '' 'sem pasta do programa para verificar'
} elseif ($marcaFaltando.Count -eq 0) {
    Item 'ok' 'aplicada (todos os arquivos no lugar)'
} else {
    Item 'aviso' "faltando: $($marcaFaltando -join ', ')"
    Detalhe 'rode o INSTALAR.bat para reaplicar'
}

Secao 'O backup'
if ($trabalhos.Count -eq 0) {
    Item 'aviso' 'nenhum trabalho de backup configurado nesta maquina'
} else {
    foreach ($t in $trabalhos) {
        $e = if ($t.Horas -gt 48) { 'erro' } elseif ($t.Horas -gt 26) { 'aviso' } else { 'ok' }
        $quando = $t.Data.ToString('dd/MM/yyyy HH:mm')
        # Numero com virgula: o resto da tela e em portugues, e "2.1 h" lido
        # por quem esta no cartorio vira "vinte e uma horas".
        $idade = if ($t.Horas -lt 48) {
            ('{0:N1} h atras' -f $t.Horas) -replace '\.', ','
        } else {
            ('{0:N1} dias atras' -f ($t.Horas / 24)) -replace '\.', ','
        }
        Item $e "ultima atividade em $quando ($idade)"
        Detalhe "$($t.Nome) - banco local de $($t.MB) MB"
    }
}

Secao 'Quedas do programa (ultimos 3 dias)'
if ($quedas.Count -eq 0) {
    Item 'ok' 'nenhuma queda registrada pelo Windows'
    if ($procs.Count -eq 0) {
        Detalhe 'entao nao travou: foi fechado, ou a maquina reiniciou sem ele voltar'
    }
} else {
    Item 'erro' "$($quedas.Count) queda(s) registrada(s) pelo Windows"
    foreach ($q in ($quedas | Select-Object -First 2)) {
        Detalhe $q.TimeCreated.ToString('dd/MM/yyyy HH:mm:ss')
        foreach ($l in (($q.Message -split "`n") | Select-Object -First 3)) {
            $x = $l.Trim(); if ($x) { Detalhe "  $x" }
        }
    }
}

# =============================================================================
#  RESOLVER
# =============================================================================

$linhas | Out-File $saida -Encoding utf8
Write-Host ''
Write-Host "  Copia deste diagnostico salva em:" -ForegroundColor DarkGray
Write-Host "     $saida" -ForegroundColor DarkGray

# Um diagnostico que so aponta o problema deixa o tecnico abrindo outro
# programa. Se o que falta e ligar o backup, ele liga.
if ($pasta -and ($procs.Count -eq 0 -or -not $portaViva)) {
    Write-Host ''
    Write-Host '  ============================================================' -ForegroundColor Cyan
    Write-Host '   Quer que eu ligue o CH.Com Backup agora? (S/N)' -ForegroundColor Cyan
    Write-Host '  ============================================================' -ForegroundColor Cyan
    $r = Read-Host '  '
    if ($r -match '^[SsYy]') {
        Write-Host ''
        Write-Host '  ligando...' -ForegroundColor Gray
        try {
            Start-Process (Join-Path $pasta 'Duplicati.GUI.TrayIcon.exe') `
                -ArgumentList '--webservice-suppress-welcome-page=true'
        } catch {
            Write-Host "  nao consegui iniciar: $($_.Exception.Message)" -ForegroundColor Red
        }
        $subiu = $false
        for ($i = 0; $i -lt 50; $i++) {
            Start-Sleep -Milliseconds 600
            try { $c = New-Object Net.Sockets.TcpClient; $c.Connect('127.0.0.1', 8200); $c.Close(); $subiu = $true; break }
            catch { }
        }
        Write-Host ''
        if ($subiu) {
            Write-Host '   BACKUP NO AR' -ForegroundColor Green
            Write-Host '   Abra no navegador: http://localhost:8200' -ForegroundColor Gray
        } else {
            Write-Host '   NAO subiu.' -ForegroundColor Red
            Write-Host '   Tente pelo atalho CH.Com Backup na area de trabalho.' -ForegroundColor Gray
            Write-Host '   Se nem assim, rode o INSTALAR.bat.' -ForegroundColor Gray
        }
    }
}

Write-Host ''
