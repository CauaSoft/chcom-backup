<#
================================================================================
  CH.Com Cofre - funcoes comuns

  Tela, registro e utilidades que todos os modulos usam.

  Este arquivo e ASCII puro de proposito. O PowerShell 5.1 le .ps1 como ANSI
  quando nao ha BOM, e acento sem BOM vira lixo na tela do servidor. Manter
  tudo em ASCII elimina a classe inteira de problema.
================================================================================
#>

# ------------------------------------------------------------------------------
#  Tela
# ------------------------------------------------------------------------------

$script:CorMarca = 'Cyan'

# A largura e fixa em 59 colunas e as linhas sao montadas com -f, nao coladas
# a mao: na primeira versao o "##" da direita ficou uma coluna fora e a caixa
# saiu torta na tela do servidor.
<#
    O cabecalho da marca.

    O preenchimento e CALCULADO, nao contado a mao. Duas tentativas de acertar
    os espacos no olho sairam tortas na tela - e uma caixa torta e a primeira
    coisa que o cliente ve.

    A linha do meio e colorida em tres pedacos (nome em branco, resto em
    cinza), entao nao da para imprimir de uma vez; o calculo garante que os
    tres pedacos somem exatamente a largura interna.
#>
function Marca {
    $largura = 59
    $dentro  = $largura - 4        # tira os "##" dos dois lados
    $nome    = 'CH.Com Cofre'
    $lema    = '  -  copia externa para desastre'
    $recuo   = '   '
    $sobra   = $dentro - $recuo.Length - $nome.Length - $lema.Length

    Write-Host ""
    Write-Host ("  " + ('#' * $largura)) -ForegroundColor DarkCyan
    Write-Host ("  ##" + (' ' * $dentro) + "##") -ForegroundColor DarkCyan
    Write-Host ("  ##" + $recuo) -ForegroundColor DarkCyan -NoNewline
    Write-Host $nome -ForegroundColor White -NoNewline
    Write-Host ($lema + (' ' * [math]::Max(0, $sobra))) -ForegroundColor Gray -NoNewline
    Write-Host "##" -ForegroundColor DarkCyan
    Write-Host ("  ##" + (' ' * $dentro) + "##") -ForegroundColor DarkCyan
    Write-Host ("  " + ('#' * $largura)) -ForegroundColor DarkCyan
}

function Secao($t) {
    Write-Host ""
    Write-Host "  $t" -ForegroundColor Cyan
    Write-Host ("  " + ("-" * 57)) -ForegroundColor DarkGray
}

function Titulo($t) { Write-Host ""; Write-Host "  $t" -ForegroundColor Cyan }
function Ok($t)     { Registrar "[OK] $t"; Write-Host "    [OK] $t" -ForegroundColor Green }
function Aviso($t)  { Registrar "[! ] $t"; Write-Host "    [! ] $t" -ForegroundColor Yellow }
function Erro($t)   { Registrar "[X ] $t"; Write-Host "    [X ] $t" -ForegroundColor Red }
function Nota($t)   { Registrar "     $t"; Write-Host "         $t" -ForegroundColor DarkGray }
function Passo($t)  { Registrar ">>> $t"; Write-Host "    ... $t" -ForegroundColor Gray }

function Caixa($linhas, $cor) {
    Write-Host ""
    Write-Host "  ===========================================================" -ForegroundColor $cor
    foreach ($l in @($linhas)) {
        Write-Host ("    " + $l) -ForegroundColor $cor
    }
    Write-Host "  ===========================================================" -ForegroundColor $cor
    Write-Host ""
}

# ------------------------------------------------------------------------------
#  Registro em arquivo
#
#  Tudo que aparece na tela vai para um arquivo tambem. Quando algo falha as
#  3 da manha num cartorio a 400 km, a tela ja fechou faz tempo.
# ------------------------------------------------------------------------------

$script:ArquivoLog = $null

function IniciarRegistro([string]$pasta, [string]$nome) {
    try {
        if (-not (Test-Path $pasta)) { New-Item -ItemType Directory -Path $pasta -Force | Out-Null }
        $script:ArquivoLog = CaminhoDe $pasta ("$nome-" + (Get-Date -Format 'yyyy-MM-dd_HHmmss') + '.txt')
        Registrar ("CH.Com Cofre - $nome - " + (Get-Date -Format 'dd/MM/yyyy HH:mm:ss'))
        Registrar "maquina: $env:COMPUTERNAME   usuario: $env:USERNAME"
        Registrar ""
    } catch { $script:ArquivoLog = $null }
}

function Registrar([string]$texto) {
    if (-not $script:ArquivoLog) { return }
    try { Add-Content -Path $script:ArquivoLog -Value $texto -Encoding UTF8 -ErrorAction SilentlyContinue } catch { }
}

# ------------------------------------------------------------------------------
#  Utilidades
# ------------------------------------------------------------------------------

<#
    Monta um caminho SEM validar a unidade.

    O Join-Path do PowerShell CONFERE se a unidade existe e LANCA erro quando
    nao existe. Numa lista de lugares POSSIVEIS - "D:\isso", "E:\aquilo" - um
    disco ausente derruba o script inteiro antes de ele chegar no disco certo.
    Isso ja aconteceu neste projeto e custou um atendimento.
#>
function CaminhoDe([string]$pasta, [string]$arquivo) {
    return ($pasta.TrimEnd('\') + '\' + $arquivo)
}

# Desliga o modo de selecao do console: um clique dentro da janela congela o
# script ate alguem apertar Esc, e quem esta no servidor acha que travou.
function DesligarCliqueQueTrava {
    try {
        if (-not ('ChCom.ModoDoConsole' -as [type])) {
            Add-Type -Name 'ModoDoConsole' -Namespace 'ChCom' -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)]
public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
'@
        }
        $h = [ChCom.ModoDoConsole]::GetStdHandle(-10)
        $modo = 0
        if ([ChCom.ModoDoConsole]::GetConsoleMode($h, [ref]$modo)) {
            [void][ChCom.ModoDoConsole]::SetConsoleMode($h, ($modo -band (-bnot 0x40)) -bor 0x80)
        }
    } catch { }
}

function EhAdministrador {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Tamanho([long]$bytes) {
    if ($bytes -ge 1TB) { return "{0:N2} TB" -f ($bytes / 1TB) }
    if ($bytes -ge 1GB) { return "{0:N2} GB" -f ($bytes / 1GB) }
    if ($bytes -ge 1MB) { return "{0:N1} MB" -f ($bytes / 1MB) }
    if ($bytes -ge 1KB) { return "{0:N0} KB" -f ($bytes / 1KB) }
    return "$bytes B"
}

function Duracao([TimeSpan]$t) {
    if ($t.TotalHours -ge 1) { return "{0:N0} h {1:N0} min" -f [math]::Floor($t.TotalHours), $t.Minutes }
    if ($t.TotalMinutes -ge 1) { return "{0:N0} min {1:N0} s" -f [math]::Floor($t.TotalMinutes), $t.Seconds }
    return "{0:N0} s" -f $t.TotalSeconds
}

<#
================================================================================
    ONDE FICAM OS DADOS - e por que NAO na pasta do programa

    O Cofre e instalado em C:\Program Files\CH.Com Cofre. Essa pasta e
    SOMENTE LEITURA para quem nao e administrador - e isso e do Windows, nao
    escolha nossa.

    A primeira versao gravava cofre.conf, rclone.conf, estado.json, historico
    e registros ali dentro. Conferido em teste: um usuario comum recebe
    "acesso ao caminho foi negado". Na pratica, o assistente falharia ao
    gravar a configuracao logo na primeira instalacao, e o historico nunca
    seria escrito.

    O lugar certo no Windows para dado de programa compartilhado entre
    usuarios e o ProgramData. E o mesmo lugar onde o proprio Duplicati, o
    SQL Server e praticamente tudo guarda estado.

        C:\Program Files\CH.Com Cofre    codigo, so leitura
        C:\ProgramData\CH.Com Cofre      configuracao, estado, historico

    Assim o motor (que roda como SYSTEM) e a janela (que roda como o usuario)
    leem e escrevem o mesmo lugar, e atualizar o programa nunca apaga a
    configuracao do cartorio.

    QUANDO O PROGRAMA NAO ESTA INSTALADO

    Rodando direto da pasta descompactada - que e como se testa - nao ha
    ProgramData ainda. Nesse caso os dados ficam ao lado do codigo, que e o
    comportamento util para teste e nao atrapalha ninguem.
================================================================================
#>
function PastaDeDados([string]$raizDoCodigo) {
    $emProgramFiles = $raizDoCodigo -like (Join-Path $env:ProgramFiles '*') -or
                      $raizDoCodigo -like (Join-Path ${env:ProgramFiles(x86)} '*')

    if (-not $emProgramFiles) { return $raizDoCodigo }

    $dados = CaminhoDe $env:ProgramData 'CH.Com Cofre'
    if (-not (Test-Path $dados)) {
        try { New-Item -ItemType Directory -Path $dados -Force -ErrorAction Stop | Out-Null }
        catch { return $raizDoCodigo }
    }
    return $dados
}

<#
    Poe aspas num caminho que vai virar argumento de linha de comando.

    Existe por causa de um defeito provado em teste: o Cofre e instalado em

        C:\Program Files\CH.Com Cofre

    que tem DOIS espacos. Passar isso para o Start-Process sem aspas faz o
    Windows quebrar o argumento no primeiro espaco - e o PowerShell recebe
    "-File C:\Program" seguido de lixo.

    O resultado seria pior que um erro visivel: os botoes da bandeja, o
    atalho e a restauracao simplesmente nao fariam nada, sem mensagem.

    Conferido: mesmo script, mesma pasta com espaco - sem aspas NAO RODOU,
    com aspas RODOU.
#>
function Aspas([string]$caminho) {
    return ('"' + $caminho + '"')
}

<#
    Quanto tempo leva para subir uma quantidade de dados.

    A conta e simples, o que importa sao as duas premissas, escritas aqui
    para nao ficarem espalhadas:

    COMPRESSAO: 50%. Conservador para .vhdx de VM Windows com disco dinamico
    e para pasta de documentos digitalizados (PDF ja e comprimido, e nao
    encolhe). Disco fixo e banco comprimem bem mais.

    O NUMERO DE Mbps E O MEDIDO CONTRA A AWS, nao o contratado. Link de
    cartorio raramente entrega o que esta no contrato, e o que decide se cabe
    na madrugada e o que ele entrega de verdade.
#>
function HorasParaEnviar([long]$bytes, [double]$mbps, [double]$compressao = 0.5) {
    # -1 significa "nao da para calcular", e e diferente de zero.
    #
    # A primeira versao devolvia 0 nos dois casos, e uma pasta de 5 GB num
    # link de 200 Mbps - que leva minutos - aparecia como "sem dados para
    # calcular". Quem lesse isso acharia que o programa nao sabia responder,
    # quando a resposta era "e rapido".
    if ($mbps -le 0 -or $bytes -le 0) { return -1 }

    $comprimido = $bytes * $compressao
    $horas = ($comprimido * 8) / ($mbps * 1MB) / 3600

    # Abaixo de 6 minutos o numero exato nao muda decisao nenhuma; o que
    # importa e que e rapido.
    if ($horas -lt 0.1) { return 0.1 }
    return [math]::Round($horas, 1)
}

# Traduz as horas para uma frase que decide alguma coisa, em vez de so um
# numero. "37 horas" nao diz nada; "nao cabe numa noite" diz.
function CabeNaJanela([double]$horas) {
    if ($horas -lt 0)   { return [PSCustomObject]@{ Estado = 'neutro'; Texto = 'sem dados para calcular' } }
    if ($horas -le 0.1) { return [PSCustomObject]@{ Estado = 'ok';     Texto = 'minutos - cabe em qualquer janela' } }
    if ($horas -le 8)   { return [PSCustomObject]@{ Estado = 'ok';     Texto = "cabe numa noite ($horas h)" } }
    if ($horas -le 24)  { return [PSCustomObject]@{ Estado = 'aviso';  Texto = "passa da madrugada ($horas h) - use o fim de semana" } }
    if ($horas -le 72)  { return [PSCustomObject]@{ Estado = 'aviso';  Texto = "leva $horas h - a primeira carga precisa ser planejada" } }
    return [PSCustomObject]@{ Estado = 'erro'; Texto = "$horas h - inviavel por este link" }
}

<#
================================================================================
    A ESTRUTURA DE DESTINO DA CH.Com

        backup-aws-ch/<CARTORIO>/<SERVIDOR>/<DISCO>/<AAAA-MM-DD>/...

    Exemplo:
        backup-aws-ch/cartorio-01/SERVIDOR-01/E/2026-08-27/...

    Nao e a estrutura padrao do rclone nem de framework nenhum: e esta, e o
    programa monta sozinho a partir do que o usuario escolheu na tela.

    O NIVEL <DISCO> QUANDO NAO HA DISCO

    Uma maquina virtual exportada, um .bak de banco e a imagem do sistema nao
    vem de um disco especifico. Deixar o nivel vazio quebraria a estrutura, e
    inventar um numero seria pior. Entao o nivel recebe um rotulo que diz o
    que e:

        E, C, D...   uma pasta ou disco daquela unidade
        VM           maquina virtual exportada
        BANCO        Firebird ou SQL Server
        SISTEMA      imagem do servidor (wbadmin)

    Assim o nivel sempre existe, sempre e legivel, e quem abrir o console da
    AWS entende o que esta olhando sem precisar do programa.
================================================================================
#>
function DiscoDaOrigem([string]$tipo, [string]$caminhoOrigem) {
    switch ($tipo) {
        'vm'        { return 'VM' }
        'firebird'  { return 'BANCO' }
        'sqlserver' { return 'BANCO' }
        'imagem'    { return 'SISTEMA' }
    }

    # Pasta ou disco: a letra da unidade, tirada do proprio caminho.
    if ($caminhoOrigem -match '^([A-Za-z]):') { return $Matches[1].ToUpper() }

    <#
        Caminho de rede, sem regex.

        Barra invertida em expressao regular escrita por script se perde no
        caminho - aconteceu tres vezes neste projeto, e uma delas o padrao
        continuou casando e devolvendo vazio, que e pior que quebrar. Metodo
        de texto nao tem o que escapar.

        "\SERVIDOR\compartilhado" nao tem letra de unidade, e o nome do
        servidor identifica a origem melhor que qualquer rotulo inventado.
    #>
    $duasBarras = [string][char]92 + [string][char]92
    if ($caminhoOrigem.StartsWith($duasBarras)) {
        $resto = $caminhoOrigem.Substring(2)
        $fim = $resto.IndexOf([char]92)
        $servidor = if ($fim -gt 0) { $resto.Substring(0, $fim) } else { $resto }
        if ($servidor) { return ('REDE-' + $servidor.ToUpper()) }
    }

    return 'OUTRO'
}

<#
    Monta o caminho completo no destino.

    Uma funcao so, usada por todo mundo, porque estrutura de destino montada
    em dois lugares vira duas estruturas diferentes no dia em que alguem
    mexer num deles.
#>
function CaminhoNoDestino {
    param(
        [Parameter(Mandatory)] [string]$Remoto,
        [Parameter(Mandatory)] [string]$Cartorio,
        [Parameter(Mandatory)] [string]$Servidor,
        [Parameter(Mandatory)] [string]$Disco,
        [Parameter(Mandatory)] [string]$Data
    )
    return "${Remoto}:$Cartorio/$Servidor/$Disco/$Data"
}

# Tira do texto o que nao pode virar nome de pasta no S3, sem inventar
# substituicao: o que nao serve vira traco, e tracos repetidos viram um.
function NomeParaDestino([string]$texto) {
    if (-not $texto) { return 'sem-nome' }
    $limpo = $texto -replace '[^A-Za-z0-9\-_.]', '-'
    while ($limpo -match '--') { $limpo = $limpo -replace '--', '-' }
    $limpo = $limpo.Trim('-')
    if (-not $limpo) { return 'sem-nome' }
    return $limpo
}

<#
    Cartorio ou gerente?

    Sao a mesma instalacao com uma diferenca: o gerente enxerga a tela
    "Todos os cartorios", que le o parque inteiro do bucket. Num cartorio essa
    tela nao pode nem existir - o operador de la nao tem por que ver a
    situacao dos outros 37 cartorios, e nem deveria saber que eles existem.

    O modo mora num arquivo ao lado do codigo, escrito pelo instalador. Nao e
    pergunta na tela: quem instala no cartorio nao pode poder errar isso.

    IMPORTANTE - isto e a INTERFACE, e nao a tranca. A tranca de verdade e o
    IAM: a credencial do cartorio so alcanca o prefixo dele. Esconder o menu
    evita confusao; quem impede o acesso e a AWS.
#>
function ModoDoPrograma([string]$raizDoCodigo) {
    $arq = CaminhoDe $raizDoCodigo 'modo.txt'
    if (-not (Test-Path $arq)) { return 'cartorio' }
    try {
        $texto = (Get-Content $arq -Raw -ErrorAction Stop).Trim().ToLower()
    } catch { return 'cartorio' }
    if ($texto -eq 'gerente') { return 'gerente' }
    return 'cartorio'
}

<#
    Uma data que pode nao existir.

    estado.json tem Terminou NULO enquanto o motor trabalha - so e preenchido
    no fim. Converter isso direto com [datetime] estoura, e estourar dentro do
    desenho da tela derruba a janela INTEIRA: quem clicou em fazer backup via
    o programa sumir da frente.

    Aqui a ausencia de data e uma resposta valida, e nao um acidente.
#>
function DataOuNada($valor) {
    if (-not $valor) { return $null }
    try { return [datetime]$valor } catch { return $null }
}

<#
    Roda o rclone sem o PowerShell confundir log com erro.

    O rclone escreve TODO o log em stderr - inclusive as linhas de nivel INFO,
    como "Copied (new)". No PowerShell 5.1, com ErrorActionPreference = Stop,
    capturar stderr de um programa externo com 2>&1 transforma CADA LINHA num
    erro terminante.

    Foi assim que o primeiro teste real contra a AWS falhou: os 8 MB subiram,
    o rclone saiu com codigo 0, e o assistente mostrou "O teste nao passou"
    exibindo uma linha de log de SUCESSO como se fosse a falha.

    Tinha um segundo estrago junto, mais silencioso: em lsjson, as linhas de
    log caiam no meio do JSON e a leitura quebrava.

    Aqui o log vai para ARQUIVO. O stdout fica limpo para quem precisa do
    JSON, e quem decide se deu certo e o codigo de saida - nao a presenca de
    texto no stderr.
#>
function RodarRclone {
    param(
        [Parameter(Mandatory)] [string]$Rclone,
        [Parameter(Mandatory)] [string[]]$Argumentos,
        [string]$Nivel = 'ERROR'
    )
    $marca = [Guid]::NewGuid().ToString('N')
    $log = CaminhoDe $env:TEMP ('cofre-rclone-' + $marca + '.log')
    $err = CaminhoDe $env:TEMP ('cofre-rclone-' + $marca + '.err')
    $r = [PSCustomObject]@{ Codigo = -1; Saida = @(); Log = @(); Erro = $null }

    <#
        Continue, e nao Stop, so aqui dentro.

        Conferido: com Stop, ATE redirecionar o stderr para arquivo com 2>
        estoura. Nao e o 2>&1 que e o problema - e o stderr de programa
        externo virar erro terminante, seja para onde for.

        Com Continue, o stderr vira arquivo de texto e quem decide se deu
        certo passa a ser o codigo de saida, que e quem sempre soube.
    #>
    $antes = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $todos = @($Argumentos) + @('--log-file', $log, '--log-level', $Nivel, '--use-json-log')
        $r.Saida = @(& $Rclone @todos 2>$err)
        $r.Codigo = $LASTEXITCODE
        if (Test-Path $log) { $r.Log = @(Get-Content $log -ErrorAction SilentlyContinue) }
        if ($r.Codigo -ne 0) {
            $solto = if (Test-Path $err) { @(Get-Content $err -ErrorAction SilentlyContinue) } else { @() }
            $r.Erro = MotivoDoRclone $r.Log $r.Codigo $solto
        }
    } catch {
        $r.Erro = $_.Exception.Message
    } finally {
        $ErrorActionPreference = $antes
        foreach ($a in @($log, $err)) { if (Test-Path $a) { Remove-Item $a -Force -ErrorAction SilentlyContinue } }
    }
    return $r
}

<#
    O motivo, e nao a ultima linha.

    O log traz centenas de linhas de INFO. Mostrar a ultima foi exatamente o
    que fez uma copia bem sucedida aparecer como falha na tela. Aqui so as
    linhas de nivel error ou fatal contam.

    E ha um caso que nao chega ao log: quando o rclone morre ANTES de abrir o
    arquivo de log - config ilegivel, remote que nao existe, permissao negada
    no proprio disco. Nesses, a explicacao so existe no stderr solto. Sem esta
    ultima rede, a tela dizia "terminou com codigo 1 e nao disse por que" -
    verdadeiro e inutil.
#>
function MotivoDoRclone($linhasDoLog, [int]$codigo, $stderrSolto = @()) {
    <#
        O rclone tem SETE niveis, e o que mata nao e o "error".

        Conferido: um remote inexistente sai como level "critical". Filtrar so
        por "error" fazia a explicacao existir no log e nao chegar na tela -
        que dizia "terminou com codigo 1 e nao disse por que", verdadeiro e
        inutil.
    #>
    $graves = @('error', 'critical', 'fatal', 'emergency')
    $erros = @()
    $avisos = @()
    foreach ($l in @($linhasDoLog)) {
        if (-not $l) { continue }
        $j = $null
        try { $j = ($l | ConvertFrom-Json) } catch { continue }
        if ($graves -contains [string]$j.level) { $erros += [string]$j.msg }
        elseif ([string]$j.level -eq 'warning') { $avisos += [string]$j.msg }
    }
    if ($erros.Count -gt 0) { return (($erros | Select-Object -Unique -First 3) -join ' | ') }

    # O stderr solto, para o que morre antes do log existir. NOTICE e recado,
    # nao erro.
    $sobra = @($stderrSolto | Where-Object { $_ -and $_.Trim() -and $_ -notmatch 'NOTICE' })
    if ($sobra.Count -gt 0) { return (($sobra | Select-Object -First 2) -join ' | ').Trim() }

    if ($avisos.Count -gt 0) { return (($avisos | Select-Object -Unique -First 2) -join ' | ') }

    return "o rclone terminou com codigo $codigo e nao disse por que"
}

<#
    Quantos fluxos ao mesmo tempo, e de que tamanho.

    O S3 aceita subir um arquivo em PEDACOS PARALELOS. Um fluxo unico quase
    nunca enche o link: ele passa metade do tempo esperando confirmacao do
    outro lado do continente. Oito pedacos ao mesmo tempo enchem.

    Mas isso custa MEMORIA, e a conta e direta:

        memoria = tamanho do pedaco x pedacos simultaneos x arquivos simultaneos

    Com 64M x 8 x 4 sao 2 GB de RAM. Num servidor de cartorio com 4 GB, isso
    derruba o Firebird junto - trocar backup lento por sistema fora do ar as
    3 da manha e um pessimo negocio.

    Entao o pedaco sai da memoria da maquina: um oitavo da RAM como teto, e o
    resto se ajusta. Servidor grande usa pedaco grande; servidor pequeno usa
    pedaco pequeno e continua vivo.
#>
function AjusteDeTransferencia {
    $ramBytes = 0
    try {
        $ramBytes = [long](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory
    } catch { $ramBytes = 4GB }
    if ($ramBytes -le 0) { $ramBytes = 4GB }

    $arquivos = 4
    $pedacos  = 8
    $teto     = [long]($ramBytes / 8)
    $pedacoMB = [int]([math]::Floor($teto / ($arquivos * $pedacos) / 1MB))

    # Piso de 5 MB porque e o minimo do S3 para envio em partes. Teto de 64 MB
    # porque acima disso o ganho some e uma queda de link custa mais caro.
    if ($pedacoMB -lt 5)  { $pedacoMB = 5 }
    if ($pedacoMB -gt 64) { $pedacoMB = 64 }

    return @{
        Arquivos = $arquivos
        Pedacos  = $pedacos
        PedacoMB = $pedacoMB
        RamGB    = [math]::Round($ramBytes / 1GB, 1)
        TetoMB   = $pedacoMB * $arquivos * $pedacos
    }
}

<#
    Le a lista do rclone sem perder os itens no caminho.

    ConvertFrom-Json, no PowerShell 5.1, devolve um array de JSON como UM
    objeto so - nao enumerado. Entao @(...) nao tem o que desembrulhar e
    guarda o array inteiro numa unica posicao.

    O estrago era grave e silencioso: quem percorria a lista pegava esse
    unico item, e $item.IsDir devolvia @(False,False,False,False) - um array
    NAO VAZIO, ou seja, verdadeiro. Todo arquivo era descartado como se fosse
    pasta, e a conferencia final dizia "o destino esta vazio" logo depois de
    um envio perfeito.

    Passava despercebido porque com UM arquivo so a conta fecha por acidente.
    Com dois ou mais - ou seja, em qualquer backup de verdade - falhava
    sempre.

    O += desembrulha um nivel, que e exatamente o que falta.
#>
function LerListaDoRclone($linhasDeSaida) {
    $itens = @()
    $texto = ($linhasDeSaida | Out-String).Trim()
    if (-not $texto) { return $itens }
    $bruto = $null
    try { $bruto = ($texto | ConvertFrom-Json) } catch { return $itens }
    if ($null -eq $bruto) { return $itens }
    $itens += $bruto
    return $itens
}

<#
    Roda QUALQUER programa externo sem confundir recado com erro.

    Mesmo caso do RodarRclone, e a lista de vitimas era maior do que parecia:
    gbak, wbadmin, robocopy e a restauracao inteira usavam 2>&1 dentro de
    scripts com ErrorActionPreference = Stop.

    Nesse arranjo, CADA LINHA que o programa escreve em stderr vira erro
    terminante - mesmo que ele esteja apenas contando o que faz e termine com
    codigo 0.

    O gbak -v e o caso mais perigoso: ele fala enquanto trabalha. Conferido
    com um programa que escreve "lendo tabela CLIENTES" no stderr e sai com
    codigo 0 - do jeito antigo, morria ali. O backup do banco do cartorio
    morreria na primeira linha de conversa.

    Aqui o stderr vai para arquivo, o stdout volta limpo, e quem diz se deu
    certo e o codigo de saida.
#>
function RodarPrograma {
    param(
        [Parameter(Mandatory)] [string]$Programa,
        # Sem Mandatory de proposito: Mandatory recusa lista vazia, e ha
        # programa que nao leva argumento nenhum.
        [string[]]$Argumentos = @()
    )
    $err = CaminhoDe $env:TEMP ('cofre-prog-' + [Guid]::NewGuid().ToString('N') + '.err')
    $r = [PSCustomObject]@{ Codigo = -1; Saida = @(); Erro = @(); Tudo = @() }

    $antes = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $r.Saida = @(& $Programa @Argumentos 2>$err)
        $r.Codigo = $LASTEXITCODE
        if (Test-Path $err) { $r.Erro = @(Get-Content $err -ErrorAction SilentlyContinue) }
        $r.Tudo = @($r.Saida) + @($r.Erro)
    } catch {
        $r.Erro = @($_.Exception.Message)
        $r.Tudo = $r.Erro
    } finally {
        $ErrorActionPreference = $antes
        if (Test-Path $err) { Remove-Item $err -Force -ErrorAction SilentlyContinue }
    }
    return $r
}

<#
    Tira o embrulho que o PowerShell poe em volta do stderr.

    Mesmo com o redirecionamento para arquivo, o PowerShell nao grava o texto
    cru: ele grava a REPRESENTACAO de um objeto de erro. Uma linha de gbak
    vira sete, com CategoryInfo, FullyQualifiedErrorId, o trecho do codigo e
    um circunflexo apontando para ele.

    Nada disso ajuda quem esta no cartorio olhando a tela. O que ajuda e a
    frase do programa - e ela e a primeira linha, depois do nome do
    executavel.
#>
function LinhasLimpas($linhas) {
    $limpas = @()
    foreach ($l in @($linhas)) {
        if ($null -eq $l) { continue }
        $t = [string]$l
        if (-not $t.Trim()) { continue }
        if ($t.StartsWith('+')) { continue }
        if ($t.TrimStart().StartsWith('+')) { continue }
        if ($t.TrimStart().StartsWith('No ')) { continue }
        if ($t -match 'CategoryInfo|FullyQualifiedErrorId|NativeCommandError|RemoteException') { continue }
        # "gbak.exe : mensagem" -> "mensagem"
        $sep = ' : '
        $p = $t.IndexOf($sep)
        if ($p -gt 0 -and $p -lt 60) { $t = $t.Substring($p + $sep.Length) }
        $limpas += $t.Trim()
    }
    return $limpas
}
