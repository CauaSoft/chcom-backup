<#
================================================================================
  CH.Com Cofre - banco de provas

  Abre o programa DE VERDADE, sem mostrar a janela, e clica em cada botao,
  cada item de menu e cada caixa de selecao - em varios cenarios: sem
  configuracao, configurado, com backup rodando, sem nada para proteger.

  POR QUE ISTO EXISTE

  Conferir na mao significa instalar, clicar em nove telas, desinstalar,
  mudar uma coisa e comecar de novo. Ninguem faz isso toda vez - entao os
  defeitos so aparecem no cartorio, que e o pior lugar para aparecerem.

  O QUE ELE NAO PROVA

  Que o backup chega na AWS. Isso exige bucket e credencial de verdade.
  Aqui se prova que a INTERFACE nao quebra, nao some e nao trava.

  USO
      powershell -ExecutionPolicy Bypass -File provar-tudo.ps1
================================================================================
#>

[CmdletBinding()]
param(
    # Roda um cenario so. Usado pelo proprio script para isolar cada cenario
    # num processo separado - se um deles derrubar o PowerShell, os outros
    # ainda rodam e o relatorio sai completo.
    [string]$Cenario = ''
)

$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
$agente = Join-Path $raiz 'agente'
$meuCaminho = $MyInvocation.MyCommand.Path
$ui = Join-Path $agente 'interface'

$CENARIOS = @(
    @{ Nome = 'sem-config';   Desc = 'primeira abertura, nada configurado' }
    @{ Nome = 'configurado';  Desc = 'ja configurado, uma copia bem sucedida' }
    @{ Nome = 'rodando';      Desc = 'com um backup em andamento' }
    @{ Nome = 'falhou';       Desc = 'ultima copia com falha' }
    @{ Nome = 'gerente';      Desc = 'modo gerente, com a tela do parque' }
)

# ------------------------------------------------------------------------------
#  Dubles
#
#  Nada aqui pode abrir processo, pedir administrador nem escrever de verdade.
#  Start-Process vira um registro do que TERIA sido chamado - e isso e mais
#  util que o efeito: prova que o botao monta o comando certo.
# ------------------------------------------------------------------------------
$script:Chamadas = @()

function Start-Process {
    $script:Chamadas += ,($args -join ' ')
    # AbrirAssistente guarda o retorno e pergunta HasExited depois.
    return ([pscustomobject]@{ Id = 0 } |
        Add-Member -Name HasExited -MemberType ScriptProperty -Value { $true } -PassThru)
}

<#
    Andar pela arvore LOGICA.

    Tudo o que este programa constroi - cada botao, cada caixa - e filho
    logico do painel onde foi colocado. A arvore VISUAL tem tudo isso mais o
    recheio dos controles do proprio Windows: as setas da barra de rolagem, o
    fundo do botao, o cursor da caixa de texto.

    Andar pela visual parecia mais completo e era pior nos dois sentidos: numa
    tela a prova nao achava o botao de verdade, e em outra ela clicou numa
    seta de barra de rolagem - um RepeatButton, que fica repetindo enquanto
    esta pressionado - e travou os 120 segundos inteiros.

    Aqui a regra e simples: so o que este programa criou.
#>
function TodosOsFilhos($no, $vistos = $null) {
    if ($null -eq $no) { return }
    if ($null -eq $vistos) { $vistos = New-Object 'System.Collections.Generic.HashSet[int]' }
    $id = [Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($no)
    if (-not $vistos.Add($id)) { return }
    $no

    try {
        foreach ($f in [Windows.LogicalTreeHelper]::GetChildren($no)) {
            if ($f -is [Windows.DependencyObject]) { TodosOsFilhos $f $vistos }
        }
    } catch { }
}

<#
    O que uma pessoa clica.

    Botao, caixa de selecao e item de menu. Fora dessa lista fica o recheio
    dos controles - RepeatButton de barra de rolagem, seta de lista - que
    ninguem clica de proposito e que ja travou a prova uma vez.
#>
function Clicaveis($raizVisual) {
    @(TodosOsFilhos $raizVisual | Where-Object {
        $_ -is [Windows.Controls.Button] -or
        $_ -is [Windows.Controls.CheckBox] -or
        $_ -is [Windows.Controls.RadioButton]
    })
}

function RotuloDe($b) {
    if ($b.Name) { return $b.Name }
    $c = $b.Content
    if ($c -is [string] -and $c) { return $c }
    if ($c -and $c.Text) { return $c.Text }
    return $b.GetType().Name
}

<#
    Clica de verdade.

    RaiseEvent com o ClickEvent e o mesmo caminho que o mouse percorre: se o
    manipulador quebrar, quebra aqui igual quebraria no cartorio.
#>
function Clicar($b) {
    $b.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
}

# ------------------------------------------------------------------------------
#  Montar o cenario
# ------------------------------------------------------------------------------
function PrepararCenario([string]$nome, [string]$pastaDados) {
    $conf = Join-Path $pastaDados 'cofre.conf'
    $est  = Join-Path $pastaDados 'estado.json'
    $modo = Join-Path $pastaDados 'modo.txt'
    foreach ($a in @($conf, $est, $modo)) { if (Test-Path $a) { Remove-Item $a -Force } }

    <#
        Uma pasta PEQUENA e nossa, e nao a do sistema.

        Apontar para %TEMP% fazia a prova varrer dezenas de milhares de
        arquivos a cada cenario. A prova tem que ser rapida o bastante para
        ser rodada sempre - uma prova que demora vira uma prova que ninguem
        roda.
    #>
    $pastaProva = Join-Path $env:TEMP 'cofre-prova-pasta'
    if (-not (Test-Path $pastaProva)) { New-Item -ItemType Directory -Path $pastaProva -Force | Out-Null }
    'conteudo de prova' | Out-File (Join-Path $pastaProva 'um.txt') -Encoding ASCII

    $temConf = $nome -ne 'sem-config'
    if ($temConf) {
        @{ Cartorio = 'cartorio-prova'; Bucket = 'backup-aws-ch'; Regiao = 'us-east-2'
           Remoto = 'cofre'; PastaDeTrabalho = $pastaProva; MbpsMedido = 12.5
           Pastas = @($pastaProva); Discos = @('C') } |
            ConvertTo-Json -Depth 5 | Out-File $conf -Encoding UTF8
    }
    if ($nome -eq 'gerente') { 'gerente' | Out-File $modo -Encoding ASCII -NoNewline }

    $agora = (Get-Date).ToUniversalTime().ToString('o')
    switch ($nome) {
        'configurado' {
            @{ Rodando = $false; Progresso = 100; Itens = 2; Sucessos = 2; Falhas = 0
               EtapaAtual = ''; ItemAtual = ''; Mensagem = 'tudo certo'
               Detalhes = @(
                 @{ Tipo='pasta'; Nome='DADOS'; Sucesso=$true; Detalhe='ok'; Bytes=1234567890; Quando=$agora }
                 @{ Tipo='vm';    Nome='SRV01'; Sucesso=$true; Detalhe='ok'; Bytes=9876543210; Quando=$agora }) } |
                ConvertTo-Json -Depth 6 | Out-File $est -Encoding UTF8
        }
        'rodando' {
            @{ Rodando = $true; Progresso = 42; Itens = 3; Sucessos = 1; Falhas = 0
               EtapaAtual = 'enviando'; ItemAtual = 'DADOS'; Mensagem = ''
               Detalhes = @(@{ Tipo='pasta'; Nome='DADOS'; Sucesso=$true; Detalhe='ok'; Bytes=1; Quando=$agora }) } |
                ConvertTo-Json -Depth 6 | Out-File $est -Encoding UTF8
        }
        'falhou' {
            @{ Rodando = $false; Progresso = 100; Itens = 2; Sucessos = 0; Falhas = 2
               EtapaAtual = ''; ItemAtual = ''; Mensagem = 'senha recusada pela AWS'
               Detalhes = @(
                 @{ Tipo='pasta'; Nome='DADOS'; Sucesso=$false; Detalhe='sem permissao'; Bytes=0; Quando=$agora }
                 @{ Tipo='vm';    Nome='SRV01'; Sucesso=$false; Detalhe='disco cheio';   Bytes=0; Quando=$agora }) } |
                ConvertTo-Json -Depth 6 | Out-File $est -Encoding UTF8
        }
    }
}

function LimparCenario([string]$pastaDados) {
    foreach ($a in @('cofre.conf','estado.json','modo.txt')) {
        $p = Join-Path $pastaDados $a
        if (Test-Path $p) { Remove-Item $p -Force }
    }
}


<#
    Roda um cenario num processo separado, COM RELOGIO.

    Sem relogio, um botao que abre caixa de dialogo trava a bateria inteira e
    ninguem descobre qual foi: a prova simplesmente nunca termina. Travar e um
    defeito tao grave quanto quebrar - entao aqui virou resultado, com nome.

    O nome do ultimo botao provado sai antes do clique, e nao depois. Assim,
    quando trava, a ultima linha do log e exatamente o culpado.
#>
function RodarFilho([string]$cenario, [string]$scriptPath, [int]$segundos = 120) {
    $log = Join-Path $env:TEMP "cofre-prova-$cenario.txt"
    $err = Join-Path $env:TEMP "cofre-prova-$cenario.err"
    foreach ($a in @($log, $err)) { if (Test-Path $a) { Remove-Item $a -Force -ErrorAction SilentlyContinue } }

    $p = Microsoft.PowerShell.Management\Start-Process powershell -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput $log -RedirectStandardError $err `
        -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass',
                        '-File', ('"' + $scriptPath + '"'), '-Cenario', $cenario)

    $travou = $false
    if (-not $p.WaitForExit($segundos * 1000)) {
        $travou = $true
        try { $p.Kill() } catch { }
        Start-Sleep -Milliseconds 300
    }

    $linhas = @()
    if (Test-Path $log) { $linhas += @(Get-Content $log) }
    if (Test-Path $err) { $linhas += @(Get-Content $err | Where-Object { $_.Trim() }) }
    foreach ($a in @($log, $err)) { if (Test-Path $a) { Remove-Item $a -Force -ErrorAction SilentlyContinue } }

    return [pscustomobject]@{ Linhas = $linhas; Travou = $travou; Segundos = $segundos }
}
# ------------------------------------------------------------------------------
#  Um cenario
# ------------------------------------------------------------------------------
function RodarUmCenario([string]$nome) {
    $falhas = @()
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms


    $menus = @('mnuParque','mnuPainel','mnuProtegido','mnuExecutar',
               'mnuRestaurar','mnuHistorico','mnuDestino','mnuChave','mnuConfig')

    foreach ($m in $menus) {
        $item = $janela.FindName($m)
        if (-not $item) { $falhas += "menu $m nao existe na janela"; continue }
        if ($item.Visibility -ne 'Visible') {
            Write-Host ("    {0,-14} escondido neste modo" -f $m)
            continue
        }

        # Trocar de tela pelo caminho real: marcar o RadioButton dispara
        # Add_Checked, que e quem chama Desenhar.
        try {
            $item.IsChecked = $true
        } catch {
            $falhas += "menu ${m}: ${_}"
            continue
        }

        $area = $janela.FindName('areaConteudo')
        $area.Measure([Windows.Size]::new(1000, 720))
        $area.Arrange([Windows.Rect]::new(0, 0, 1000, 720))

        if ($area.Children.Count -eq 0) {
            $falhas += "menu ${m}: a tela abriu VAZIA"
            Write-Host ("    {0,-14} [X] TELA VAZIA" -f $m)
            continue
        }

        $botoes = Clicaveis $area
        $quebrou = 0
        foreach ($b in $botoes) {
            $rot = RotuloDe $b
            if (-not $b.IsEnabled) { continue }
            Write-Host ("PROVANDO::" + $m + " / " + $rot)
            try {
                Clicar $b
                # Depois de cada clique a tela pode ter sido redesenhada.
                $area.Measure([Windows.Size]::new(1000, 720))
                $area.Arrange([Windows.Rect]::new(0, 0, 1000, 720))
                if ($area.Children.Count -eq 0) {
                    $falhas += "menu ${m}, botao '${rot}': a tela ficou VAZIA depois do clique"
                    $quebrou++
                }
            } catch {
                $falhas += "menu ${m}, botao '${rot}': $($_.Exception.Message)"
                $quebrou++
            }
            # Volta para a tela do menu: um clique pode ter navegado para outra.
            $item.IsChecked = $true
            $area = $janela.FindName('areaConteudo')
        }
        $sinal = if ($quebrou -gt 0) { '[X]' } else { '[OK]' }
        Write-Host ("    {0,-14} {1} {2} botao(oes)" -f $m, $sinal, $botoes.Count)
    }

    # Os botoes do cabecalho, fora da area de conteudo.
    foreach ($n in @('btnAtualizar')) {
        $b = $janela.FindName($n)
        if (-not $b) { $falhas += "botao $n nao existe"; continue }
        try { Clicar $b; Write-Host ("    {0,-14} [OK]" -f $n) }
        catch { $falhas += "botao ${n}: $($_.Exception.Message)"; Write-Host ("    {0,-14} [X]" -f $n) }
    }

    return $falhas
}

# ------------------------------------------------------------------------------
#  O assistente
# ------------------------------------------------------------------------------
function RodarAssistente {
    $falhas = @()
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

    for ($p = 1; $p -le 7; $p++) {
        $W.Passo = $p
        try {
            Renderizar
            $c = $janela.Content
            $c.Measure([Windows.Size]::new(980, 700))
            $c.Arrange([Windows.Rect]::new(0, 0, 980, 700))
        } catch {
            $falhas += "assistente passo ${p}: nao desenhou - $($_.Exception.Message)"
            Write-Host ("    passo {0}        [X] nao desenhou" -f $p)
            continue
        }

        <#
            Botoes que so uma pessoa pode responder.

            btnAvancar e btnVoltar mudam o passo e baguncam a contagem - eles
            sao provados a parte, andando do 1 ao 7.

            btnCancelar abre um "tem certeza?" e fica esperando alguem clicar
            Sim ou Nao. A prova nao tem dedo: ela travava ali, e o relogio de
            120 segundos foi quem contou a historia. Ficam declarados aqui, e
            nao escondidos - quem le o relatorio precisa saber o que NAO foi
            provado sozinho.
        #>
        $soComPessoa = @('btnAvancar','btnVoltar','btnSair','btnCancelar')
        $botoes = @(Clicaveis $janela.Content | Where-Object { $_.Name -notin $soComPessoa })
        $quebrou = 0
        foreach ($b in $botoes) {
            if (-not $b.IsEnabled) { continue }
            $rot = RotuloDe $b
            Write-Host ("PROVANDO::passo " + $p + " / " + $rot)
            try { Clicar $b } catch {
                $falhas += "assistente passo ${p}, botao '${rot}': $($_.Exception.Message)"
                $quebrou++
            }
            $W.Passo = $p
            try { Renderizar } catch {
                $falhas += "assistente passo ${p}: nao redesenhou depois de '${rot}' - $($_.Exception.Message)"
                $quebrou++
            }
        }
        $sinal = if ($quebrou -gt 0) { '[X]' } else { '[OK]' }
        Write-Host ("    passo {0}        {1} {2} botao(oes)" -f $p, $sinal, $botoes.Count)
    }

    # Andar pelos passos como uma pessoa anda: Avancar ate o fim, Voltar ate o
    # comeco. E aqui que aparecem os becos sem saida - o passo que se recusa a
    # avancar e nao diz por que.
    <#
        Andar pelos passos como uma pessoa anda.

        Os campos sao PREENCHIDOS antes: sem isso a prova para no passo 2 e
        nunca chega nos passos 3 a 7, que sao justamente onde estao as
        escolhas de disco, pasta e chave. Uma prova que para no comeco da a
        impressao de que passou.

        Os valores sao de mentira de proposito - nenhuma credencial de
        verdade entra num script de teste.
    #>
    $W.Passo = 1
    Renderizar
    $preencher = @{
        cartorio   = 'cartorio-prova'
        bucket     = 'backup-aws-ch'
        regiao     = 'us-east-2'
        chaveAws   = 'chave-de-mentira-para-a-prova'
        segredoAws = 'segredo-de-mentira-so-para-a-prova'
    }
    for ($i = 1; $i -le 6; $i++) {
        foreach ($nome in $preencher.Keys) {
            $caixa = $W.Caixas[$nome]
            if (-not $caixa) { continue }
            if ($caixa -is [Windows.Controls.PasswordBox]) { $caixa.Password = $preencher[$nome] }
            else { $caixa.Text = $preencher[$nome] }
        }
        <#
            O passo 3 exige ao menos um disco ou pasta escolhido.

            Os cliques da etapa anterior passaram por todas as caixas de
            selecao da tela - inclusive DESMARCANDO o que estava marcado. Sem
            remarcar aqui, o passeio parava no 3 e as telas 4 a 7 deixavam de
            ser provadas em silencio: o relatorio dizia "chegou ao passo 3" e
            ninguem lia aquilo como perda de cobertura.
        #>
        if ($W.Discos.Count -eq 0 -and $W.Pastas.Count -eq 0) {
            $primeiro = @($W.Ambiente.Discos | Where-Object { $_.ServeParaTrabalho })[0]
            if ($primeiro) { $W.Discos = @($primeiro.Unidade) }
        }
        $antes = $W.Passo
        try { Clicar ($janela.FindName('btnAvancar')) } catch {
            $falhas += "assistente: Avancar quebrou no passo ${antes} - $($_.Exception.Message)"
            break
        }
        if ($W.Passo -eq $antes) {
            Write-Host ("    avancar        passo {0} nao avanca (falta preencher)" -f $antes)
            break
        }
    }
    Write-Host ("    avancar        chegou ao passo {0} de 7" -f $W.Passo)
Write-Host '    (btnCancelar fica de fora: abre um Sim/Nao que so uma pessoa responde)'
    return $falhas
}

# ------------------------------------------------------------------------------
#  Quem manda
# ------------------------------------------------------------------------------
if ($Cenario) {
    <#
        Rodando isolado, a mando do processo principal.

        O programa e carregado AQUI, no escopo do script - e nao dentro de uma
        funcao. GetNewClosure, que a interface usa em todo botao, cria um
        escopo filho do escopo do SCRIPT: funcao declarada dentro de outra
        funcao fica invisivel para ela, e todo clique morreria com "o termo
        'Desenhar' nao e reconhecido".

        Aqui isso era defeito da prova, nao do produto - mas e o mesmo tropeco
        que ja derrubou o menu de verdade uma vez.
    #>
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms
    if ($Cenario -eq 'assistente') {
        . (Join-Path $ui 'assistente.ps1') -NaoAbrir
        $saida = RodarAssistente
    } else {
        . (Join-Path $ui 'cofre-ui.ps1') -NaoAbrir
        $saida = RodarUmCenario $Cenario
    }
    foreach ($f in $saida) { Write-Host "FALHA::$f" }
    exit 0
}

Write-Host ''
Write-Host '  ============================================================'
Write-Host '    CH.Com Cofre - banco de provas'
Write-Host '  ============================================================'

# --- 1. sintaxe ---
Write-Host ''
Write-Host '  1. Sintaxe de todo o projeto'
$comErro = 0; $n = 0
foreach ($f in @(Get-ChildItem $raiz -Recurse -Include *.ps1 -File |
                 Where-Object { $_.FullName -notlike '*\dist\*' })) {
    $n++
    $tok = $null; $err = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tok, [ref]$err)
    if ($err.Count -gt 0) {
        $comErro++
        Write-Host ("    [X] {0} linha {1}: {2}" -f $f.Name, $err[0].Extent.StartLineNumber, $err[0].Message)
    }
}
Write-Host ("    {0} scripts, {1} com erro" -f $n, $comErro)

# --- 2. telas XAML ---
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Write-Host ''
Write-Host '  2. Telas XAML'
$xErro = 0; $nx = 0
foreach ($f in @(Get-ChildItem $raiz -Recurse -Include *.xaml -File |
                 Where-Object { $_.FullName -notlike '*\dist\*' })) {
    $nx++
    try {
        $x = [xml](Get-Content $f.FullName -Raw)
        [void][Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $x))
    } catch { $xErro++; Write-Host ("    [X] {0}: {1}" -f $f.Name, $_.Exception.Message) }
}
Write-Host ("    {0} telas, {1} com erro" -f $nx, $xErro)

# --- 3. os cenarios ---
. (Join-Path $agente 'modulos\comum.ps1')
$dados = PastaDeDados $agente
$todasAsFalhas = @()

Write-Host ''
# Um processo filho que escreve em stderr NAO e motivo para abortar a bateria:
# e justamente o que se quer capturar e relatar no fim.
$ErrorActionPreference = 'Continue'
Write-Host '  3. A janela, cenario por cenario'
foreach ($c in $CENARIOS) {
    Write-Host ''
        $ultimo = "(nada ainda)"
    Write-Host ("  -- {0}: {1}" -f $c.Nome, $c.Desc)
    PrepararCenario $c.Nome $dados
    try {
        $r = RodarFilho $c.Nome $meuCaminho
        foreach ($linha in $r.Linhas) {
            $t = [string]$linha
            if ($t.StartsWith("FALHA::")) { $todasAsFalhas += ($c.Nome + " | " + $t.Substring(7)) }
            elseif ($t.StartsWith("PROVANDO::")) { $ultimo = $t.Substring(10) }
            elseif ($t.Trim()) { Write-Host $t }
        }
        if ($r.Travou) {
            $ultima = $ultimo
            $todasAsFalhas += ("{0} | TRAVOU - passou de {1}s sem terminar. Ultima coisa provada: {2}" -f `
                $c.Nome, $r.Segundos, $ultima)
            Write-Host ("    [X] TRAVOU depois de: {0}" -f $ultima)
        }
    } finally { LimparCenario $dados }
}

# --- 4. o assistente ---
Write-Host ''
Write-Host '  4. O assistente, passo a passo'
PrepararCenario 'sem-config' $dados
try {
    $ultimo = "(nada ainda)"
    $r = RodarFilho 'assistente' $meuCaminho
    foreach ($linha in $r.Linhas) {
        $t = [string]$linha
        if ($t.StartsWith("FALHA::")) { $todasAsFalhas += ("assistente | " + $t.Substring(7)) }
        elseif ($t.StartsWith("PROVANDO::")) { $ultimo = $t.Substring(10) }
        elseif ($t.Trim()) { Write-Host $t }
    }
    if ($r.Travou) {
        $ultima = $ultimo
        $todasAsFalhas += ("assistente | TRAVOU - passou de {0}s sem terminar. Ultima coisa provada: {1}" -f `
            $r.Segundos, $ultima)
        Write-Host ("    [X] TRAVOU depois de: {0}" -f $ultima)
    }
} finally { LimparCenario $dados }

# --- 5. os atalhos .bat ---
Write-Host ''
Write-Host '  5. Atalhos .bat'
foreach ($b in @(Get-ChildItem $agente -Filter *.bat -File)) {
    $txt = Get-Content $b.FullName -Raw
    # Caminho proprio sem aspas: em pasta com espaco o .bat nao roda e nao
    # avisa. Ja aconteceu uma vez.
    if ($txt -match '-FilePath\s+%~f0') {
        $todasAsFalhas += ("bat | {0}: -FilePath %~f0 SEM ASPAS - nao roda em pasta com espaco" -f $b.Name)
        Write-Host ("    [X] {0}  caminho sem aspas" -f $b.Name)
        continue
    }
    # Pedido de elevacao sem marcador: se 'net session' falhar por outro
    # motivo, vira uma fila infinita de avisos do Windows.
    if ($txt -match 'Verb RunAs' -and $txt -notmatch 'ArgumentList ''elevado''') {
        $todasAsFalhas += ("bat | {0}: eleva sem marcador - risco de pedir UAC em circulo" -f $b.Name)
        Write-Host ("    [X] {0}  eleva sem marcador" -f $b.Name)
        continue
    }
    $alvos = [regex]::Matches($txt, '%~dp0([^"]+)') | ForEach-Object { $_.Groups[1].Value }
    $faltou = @($alvos | Where-Object { -not (Test-Path (Join-Path $agente $_)) })
    if ($faltou.Count -gt 0) {
        $todasAsFalhas += ("bat | {0}: aponta para {1}, que nao existe" -f $b.Name, ($faltou -join ', '))
        Write-Host ("    [X] {0}  aponta para arquivo que nao existe" -f $b.Name)
    } else {
        Write-Host ("    [OK] {0}" -f $b.Name)
    }
}


# --- 6. arquivos citados nas mensagens ---
<#
    Mandar o usuario rodar um arquivo que nao existe.

    Seis mensagens da interface mandavam rodar o INSTALAR-COFRE.bat, que
    deixou de existir quando o instalador virou INSTALAR.bat. Ninguem percebe
    isso lendo o codigo - so o cartorio percebe, procurando um arquivo que
    nao esta la.
#>
Write-Host ''
Write-Host '  6. Arquivos citados nas mensagens'
$citados = @{}
foreach ($f in @(Get-ChildItem $agente -Recurse -Include *.ps1 -File)) {
    foreach ($m in [regex]::Matches((Get-Content $f.FullName -Raw), '[A-Za-z0-9\-\.]+\.bat')) {
        $citados[$m.Value] = $f.Name
    }
}
$fantasmas = 0
foreach ($nome in $citados.Keys) {
    if (-not (Test-Path (Join-Path $agente $nome))) {
        $fantasmas++
        $todasAsFalhas += ("texto | {0} manda rodar '{1}', que nao existe no pacote" -f $citados[$nome], $nome)
        Write-Host ("    [X] {0} citado em {1} - nao existe" -f $nome, $citados[$nome])
    }
}
if ($fantasmas -eq 0) {
    Write-Host ("    {0} arquivo(s) citados, todos existem" -f $citados.Count)
}
# --- veredito ---
Write-Host ''
Write-Host '  ============================================================'
if ($todasAsFalhas.Count -eq 0 -and $comErro -eq 0 -and $xErro -eq 0) {
    Write-Host '    TUDO PASSOU - nenhum botao quebrou, nenhuma tela sumiu'
    Write-Host '  ============================================================'
    Write-Host ''
    exit 0
}
Write-Host ("    {0} PROBLEMA(S)" -f ($todasAsFalhas.Count + $comErro + $xErro))
Write-Host '  ============================================================'
foreach ($f in $todasAsFalhas) { Write-Host ("    - {0}" -f $f) }
Write-Host ''
exit 1
