<#
================================================================================
  CH.Com Cofre - assistente de configuracao

  Tudo o que antes era pergunta no console agora acontece aqui: nome do
  cartorio, destino na AWS, credenciais, chave, teste e agendamento.

  POR QUE ISSO SAIU DO CONSOLE

  Quem instala num cartorio nao deveria precisar abrir PowerShell, nem
  responder pergunta em tela preta, nem lembrar de rodar um segundo comando
  depois do primeiro. O programa e instalado e configurado numa coisa so.

  O QUE NAO MUDOU

  A chave continua sendo o unico passo que NAO DA PARA PULAR. Aqui isso e um
  botao que so habilita depois de a pessoa marcar que guardou - e o texto
  explica por que, em vez de so mandar.
================================================================================
#>

[CmdletBinding()]
param([switch]$NaoAbrir)

$ErrorActionPreference = 'Stop'

<#
    QUANDO O ASSISTENTE QUEBRA ANTES DE APARECER

    Ele roda com o console oculto, num processo separado e elevado. Se
    estourar um erro antes da janela subir, nao sobra nada na tela: quem
    clicou em "Configurar agora" ve o programa simplesmente nao fazer nada.

    Aqui a falha vira duas coisas visiveis - uma caixa na tela agora, e um
    arquivo para ser lido depois, no cartorio, sem ninguem por perto.
#>
trap {
    $quebra = $_
    $pasta = Join-Path $env:ProgramData 'CH.Com Cofre'
    if (-not (Test-Path $pasta)) { $pasta = $env:TEMP }
    $arquivo = Join-Path $pasta 'erro-assistente.txt'
    $nl = [Environment]::NewLine
    $texto = ('CH.Com Cofre - o assistente parou' + $nl +
              (Get-Date -Format 'dd/MM/yyyy HH:mm:ss') + $nl + $nl +
              $quebra.Exception.Message + $nl + $nl + $quebra.ScriptStackTrace)
    try { $texto | Out-File -FilePath $arquivo -Encoding UTF8 -Force } catch { }
    try {
        [Windows.MessageBox]::Show(
            ('O assistente nao conseguiu abrir.' + $nl + $nl + $quebra.Exception.Message +
             $nl + $nl + 'Detalhes gravados em:' + $nl + $arquivo),
            'CH.Com Cofre', 'OK', 'Error') | Out-Null
    } catch { }
    exit 1
}
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

$aqui = Split-Path -Parent $MyInvocation.MyCommand.Path
$raiz = Split-Path -Parent $aqui

foreach ($m in @('comum','descobrir','planejar','configurar','enviar')) {
    . (Join-Path $raiz "modulos\$m.ps1")
}
. (Join-Path $aqui 'componentes.ps1')

# Configuracao, estado e historico ficam em ProgramData, e nao ao lado do
# codigo: Program Files e somente leitura para quem nao e administrador.
$dados = PastaDeDados $raiz

$xml = [xml](Get-Content (CaminhoDe $aqui 'assistente.xaml') -Raw)
$janela = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xml))

# A barra de rolagem e os demais estilos comuns vem de estilos.xaml, um
# arquivo so: estilo duplicado nos dois XAML sai de sincronia, e foi assim
# que os botoes do assistente ficaram com nome diferente dos da janela.
[void](AplicarEstilosCompartilhados $janela $aqui)

$pastaMarca = CaminhoDe $raiz 'marca'
try {
    $img = New-Object Windows.Media.Imaging.BitmapImage
    $img.BeginInit()
    $img.UriSource = New-Object Uri((CaminhoDe $pastaMarca 'logo-256.png'))
    $img.CacheOption = 'OnLoad'
    $img.EndInit()
    $janela.FindName('imgLogo').Source = $img
} catch { }
<#
    O maior quadro do .ico, e nao o primeiro - mesmo caso da janela principal.

    O BitmapImage pega sempre a menor imagem de dentro do .ico, seja qual for
    a ordem no arquivo, e o assistente abria com um icone de 16 pixels
    esticado. IconeGrande vem do cofre-ui.ps1 quando ele ja esta carregado; se
    o assistente rodar sozinho, a copia local resolve.
#>
if (-not (Get-Command IconeGrande -ErrorAction SilentlyContinue)) {
    function IconeGrande([string]$arquivo) {
        if (-not (Test-Path $arquivo)) { return $null }
        try {
            $fluxo = [IO.File]::OpenRead($arquivo)
            try {
                $dec = New-Object Windows.Media.Imaging.IconBitmapDecoder(
                    $fluxo,
                    [Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,
                    [Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
                $maior = $null
                foreach ($q in $dec.Frames) {
                    if (-not $maior -or $q.PixelWidth -gt $maior.PixelWidth) { $maior = $q }
                }
                return $maior
            } finally { $fluxo.Dispose() }
        } catch { return $null }
    }
}
$ico = IconeGrande (CaminhoDe $pastaMarca 'chcom.ico')
if ($ico) { $janela.Icon = $ico }

# Estado do assistente. Hashtable pelo mesmo motivo da janela principal: os
# manipuladores de clique usam GetNewClosure(), que da a eles um escopo de
# script proprio - variavel $script: dentro deles escreve em outro lugar.
$W = @{
    Passo     = 1
    Total     = 7
    Ambiente  = $null
    Plano     = $null
    Cartorio  = ''
    Bucket    = 'backup-aws-ch'
    Regiao    = 'us-east-2'
    ChaveAws  = ''
    SegredoAws = ''
    Trabalho  = ''
    Chave     = $null
    Guardou   = $false
    Testou    = $false
    Erro      = ''
    Pastas    = @()
    Discos    = @()
    TamanhoDasPastas = @{}
    Mbps      = 0
    Caixas    = @{}
}

$area = $janela.FindName('areaPasso')
$btnAvancar = $janela.FindName('btnAvancar')
$btnVoltar = $janela.FindName('btnVoltar')
$btnCancelar = $janela.FindName('btnCancelar')

# ==============================================================================
#  Os passos
# ==============================================================================

function Passo1_Bemvindo {
    $sp = New-Object Windows.Controls.StackPanel

    $sp.Children.Add((FaixaVeredito 'info' 'O Cofre olhou este servidor' `
        "Estrategia: $($W.Plano.Estrategia)")) | Out-Null

    $sp.Children.Add((NovoTexto (
        'Esta e a copia externa para desastre. Ela nao substitui o backup que o cartorio ja ' +
        'tem: existe para o caso de perda total - incendio, roubo, ou os servidores irem ' +
        'embora de uma vez.') 13 $Cores.Texto2)) | Out-Null

    $sp.Children.Add((Secao 'O que sera protegido aqui' '')) | Out-Null

    $c = NovoCartao
    $inner = New-Object Windows.Controls.StackPanel
    if ($W.Plano.Tarefas.Count -eq 0) {
        $inner.Children.Add((LinhaItem 'outro' 'Nada foi identificado' `
            'Sem VM, sem banco e sem imagem de sistema, nao ha o que o Cofre proteja aqui.' `
            'erro' '' '')) | Out-Null
    }
    foreach ($t in $W.Plano.Tarefas) {
        $est = if ($t.Porque -match 'CRASH') { 'aviso' } else { 'ok' }
        $inner.Children.Add((LinhaItem $t.Tipo $t.Nome $t.Porque $est $t.Frequencia '')) | Out-Null
    }
    $c.Child = $inner
    $sp.Children.Add($c) | Out-Null

    <#
        Quando a deteccao nao acha nada, o passo 1 explica o proximo passo em
        vez de so mostrar vermelho.

        Instalar o Cofre DENTRO de uma VM e um caso normal - e o jeito de
        proteger o banco que roda ali dentro, que o host nao alcanca. Nessa
        VM nao ha "VM para exportar" nem imagem de sistema, e nao deveria:
        o que ela tem sao pastas, e pastas se escolhem no passo seguinte.
    #>
    if ($W.Plano.Tarefas.Count -eq 0) {
        $sp.Children.Add((BlocoAviso 'info' (
            'A deteccao nao achou maquina virtual nem banco de dados aqui - e isso pode estar ' +
            'certo. E o caso, por exemplo, de instalar o Cofre DENTRO de uma maquina virtual, ' +
            'onde o que importa sao as pastas de dados. ' +
            'Continue: no passo 3 voce escolhe os discos e as pastas que devem ir para o Cofre.'))) | Out-Null
    }

    foreach ($n in $W.Plano.NaoProtegido) {
        $sp.Children.Add((BlocoAviso 'perigo' "NAO PROTEGIDO: $n")) | Out-Null
    }
    foreach ($a in $W.Plano.Avisos) {
        $sp.Children.Add((BlocoAviso 'aviso' $a)) | Out-Null
    }

    return $sp
}

function Passo2_Destino {
    $sp = New-Object Windows.Controls.StackPanel

    $sp.Children.Add((NovoTexto (
        'O Cofre grava cada copia direto na classe Glacier Deep Archive, sem regra de ciclo ' +
        'de vida. O bucket precisa existir na sua conta da AWS.') 13 $Cores.Texto2)) | Out-Null

    $esp = New-Object Windows.Controls.Border; $esp.Height = 22
    $sp.Children.Add($esp) | Out-Null

    $c1 = CampoTexto 'Nome curto do cartorio' $W.Cartorio 'Vira a pasta na nuvem. Sem espaco e sem acento. Ex: cartorio-ji-parana'
    $sp.Children.Add($c1.Elemento) | Out-Null
    $W.Caixas['cartorio'] = $c1.Caixa

    $c2 = CampoTexto 'Bucket na AWS' $W.Bucket 'O nome exato do bucket S3, ja criado na sua conta'
    $sp.Children.Add($c2.Elemento) | Out-Null
    $W.Caixas['bucket'] = $c2.Caixa

    $c3 = CampoTexto 'Regiao' $W.Regiao 'us-east-2 e Ohio. Precisa ser a mesma regiao do bucket.'
    $sp.Children.Add($c3.Elemento) | Out-Null
    $W.Caixas['regiao'] = $c3.Caixa

    # --- area de trabalho, escolhida entre discos LOCAIS ---
    $sp.Children.Add((Secao 'Area de trabalho' 'Onde a copia e montada antes de subir')) | Out-Null

    $maior = 0
    foreach ($v in $W.Ambiente.VMs) { if ($v.TamanhoBytes -gt $maior) { $maior = $v.TamanhoBytes } }
    $precisa = if ($maior) { [long]($maior * 1.2) } else { 20GB }

    $locais = @($W.Ambiente.Discos | Where-Object { $_.ServeParaTrabalho } |
                Sort-Object LivreBytes -Descending)

    $c = NovoCartao
    $inner = New-Object Windows.Controls.StackPanel
    $inner.Children.Add((NovoTexto "Precisa de pelo menos $(Tamanho $precisa)" 12 $Cores.Texto3)) | Out-Null
    $espaco = New-Object Windows.Controls.Border; $espaco.Height = 10
    $inner.Children.Add($espaco) | Out-Null

    $escolhido = $null
    foreach ($d in $locais) {
        $serve = ($d.LivreBytes -ge $precisa)
        if ($serve -and -not $escolhido) { $escolhido = $d }
        $inner.Children.Add((LinhaItem 'disco' "Unidade $($d.Unidade):" `
            "$(Tamanho $d.LivreBytes) livres de $(Tamanho $d.TotalBytes)" `
            $(if ($serve) { 'ok' } else { 'erro' }) `
            $(if ($serve) { 'serve' } else { 'insuficiente' }) '')) | Out-Null
    }

    # Unidade de REDE nunca serve, mesmo com espaco de sobra: um OneDrive
    # mapeado empurraria 200 GB de VM para a nuvem errada.
    foreach ($d in @($W.Ambiente.Discos | Where-Object { -not $_.ServeParaTrabalho })) {
        $inner.Children.Add((LinhaItem 'disco' "Unidade $($d.Unidade):" `
            "$($d.Tipo) - nao serve de area de trabalho" 'neutro' '' '')) | Out-Null
    }

    $c.Child = $inner
    $sp.Children.Add($c) | Out-Null

    if ($escolhido) {
        $W.Trabalho = CaminhoDe ($escolhido.Unidade + ':') 'CH.Com Cofre'
        $sp.Children.Add((BlocoAviso 'info' "Sera usada: $($W.Trabalho)")) | Out-Null
    } else {
        $W.Trabalho = ''
        $sp.Children.Add((BlocoAviso 'perigo' (
            'Nenhum disco local tem espaco suficiente. Libere espaco ou acrescente um disco ' +
            'antes de continuar - o Cofre monta a copia em disco antes de enviar.'))) | Out-Null
    }

    return $sp
}

<#
    As pastas do cartorio.

    O agente descobre VM, banco e imagem de sistema sozinho. Pasta, nao: nao
    ha como adivinhar que "Z:\DADOS\Escrituras" importa e "C:\temp" nao. So
    quem conhece o cartorio sabe.

    Por isso este passo existe - e por isso ele usa um SELETOR de pasta em vez
    de um campo de texto. Caminho digitado a mao erra, e o erro so aparece na
    primeira madrugada, quando o Cofre nao acha a pasta.
#>
<#
    A origem: o que vai para o Cofre.

    Discos inteiros e pastas escolhidas, com o calculo do tempo atualizando a
    cada marcacao.

    POR QUE O CALCULO FICA AQUI, E NAO SO NO FIM

    A pergunta que decide tudo e "cabe na madrugada?". Deixar isso para
    descobrir na primeira execucao significa instalar em 50 cartorios e so
    entao saber em quais nao cabe. Marcando o disco e vendo "37 h - passa da
    madrugada" na hora, a decisao e tomada com a pessoa ainda na frente do
    servidor.

    O tamanho do DISCO e instantaneo: usado = total menos livre, direto do
    volume. Varrer arquivo por arquivo levaria minutos, travaria a janela, e
    chegaria no mesmo numero.
#>
function Passo3_Origem {
    $sp = New-Object Windows.Controls.StackPanel

    $sp.Children.Add((NovoTexto (
        'Escolha o que o Cofre vai copiar. Maquinas virtuais e bancos ja entram sozinhos - ' +
        'aqui ficam os discos e as pastas, que o agente nao tem como adivinhar.') 13 $Cores.Texto2)) | Out-Null

    # --- o calculo, no topo, porque e o que decide ---
    $bytes = 0
    foreach ($d in $W.Ambiente.Discos) {
        if ($W.Discos -contains $d.Unidade) { $bytes += [long]($d.TotalBytes - $d.LivreBytes) }
    }
    foreach ($p in $W.Pastas) {
        if ($W.TamanhoDasPastas.ContainsKey($p)) { $bytes += [long]$W.TamanhoDasPastas[$p] }
    }
    foreach ($v in $W.Ambiente.VMs) { $bytes += [long]$v.TamanhoBytes }

    $painel = PainelDoCalculo $bytes $W.Mbps
    $painel.Margin = '0,18,0,4'
    $sp.Children.Add($painel) | Out-Null

    <#
        O destino de cada item aparece na tela, montado pelas MESMAS funcoes
        que o motor usa na hora de enviar.

        Nao e um exemplo: e o caminho que vai existir na AWS. Escolher uma
        pasta sem saber onde ela vai parar e o tipo de erro que so aparece no
        dia da restauracao, com alguem procurando num bucket que tem outra
        estrutura na cabeca.

        Depende do nome do cartorio, que vem do passo 2 - por isso o exemplo
        so aparece depois de ele estar preenchido.
    #>
    $cartorioMostrar = if ($W.Cartorio) { NomeParaDestino $W.Cartorio } else { '<cartorio>' }
    $servidorMostrar = NomeParaDestino $W.Ambiente.Maquina
    $hoje = Get-Date -Format 'yyyy-MM-dd'

    function DestinoDe([string]$tipo, [string]$origem, [string]$nome) {
        $d = DiscoDaOrigem $tipo $origem
        $p = CaminhoNoDestino -Remoto $W.Bucket -Cartorio $cartorioMostrar `
                -Servidor $servidorMostrar -Disco $d -Data $hoje
        # Mostra o bucket, e nao o nome do remote do rclone: quem abrir o
        # console da AWS vai procurar pelo bucket.
        return ($p -replace '^[^:]+:', ($W.Bucket + '/')) + '/' + (NomeParaDestino $nome)
    }

    # --- discos ---
    # --- discos ---
    $sp.Children.Add((Secao 'Discos deste servidor' 'Marque os que devem ir inteiros para o Cofre')) | Out-Null
    $c = NovoCartao
    $inner = New-Object Windows.Controls.StackPanel

    foreach ($d in $W.Ambiente.Discos) {
        $unidade = $d.Unidade
        $linha = LinhaDisco $d ($W.Discos -contains $unidade) {
            $marcado = $this.IsChecked
            if ($marcado) {
                if ($W.Discos -notcontains $unidade) { $W.Discos = @($W.Discos) + $unidade }
            } else {
                $W.Discos = @($W.Discos | Where-Object { $_ -ne $unidade })
            }
            Renderizar
        }.GetNewClosure()
        $inner.Children.Add($linha.Elemento) | Out-Null
        if ($W.Discos -contains $unidade) {
            $inner.Children.Add((LinhaDestino (DestinoDe 'pasta' ($unidade + ':\') "Disco $unidade"))) | Out-Null
        }
    }

    $c.Child = $inner
    $sp.Children.Add($c) | Out-Null

    # --- pastas ---
    $sp.Children.Add((Secao 'Pastas escolhidas' 'Para quando so uma parte do disco importa')) | Out-Null
    $c2 = NovoCartao
    $in2 = New-Object Windows.Controls.StackPanel

    if ($W.Pastas.Count -eq 0) {
        $in2.Children.Add((NovoTexto 'Nenhuma pasta escolhida.' 13 $Cores.Texto3)) | Out-Null
    }

    foreach ($p in $W.Pastas) {
        $linha = New-Object Windows.Controls.Grid
        $ca = New-Object Windows.Controls.ColumnDefinition; $ca.Width = '*'
        $cb = New-Object Windows.Controls.ColumnDefinition; $cb.Width = 'Auto'
        $linha.ColumnDefinitions.Add($ca) | Out-Null
        $linha.ColumnDefinitions.Add($cb) | Out-Null

        $tam = if ($W.TamanhoDasPastas.ContainsKey($p)) { Tamanho ([long]$W.TamanhoDasPastas[$p]) } else { 'medindo...' }
        $item = LinhaItem 'disco' $p "copia de sombra - le arquivo aberto" 'ok' '' $tam
        [Windows.Controls.Grid]::SetColumn($item, 0)
        $linha.Children.Add($item) | Out-Null

        $estaPasta = $p
        $bx = NovoBotao 'Tirar' $Icones.Erro $false $janela
        $bx.Height = 34
        $bx.Margin = '8,0,0,8'
        $bx.VerticalAlignment = 'Center'
        $bx.Add_Click({
            $W.Pastas = @($W.Pastas | Where-Object { $_ -ne $estaPasta })
            Renderizar
        }.GetNewClosure())
        [Windows.Controls.Grid]::SetColumn($bx, 1)
        $linha.Children.Add($bx) | Out-Null

        $in2.Children.Add($linha) | Out-Null
        $in2.Children.Add((LinhaDestino (DestinoDe 'pasta' $p (Split-Path $p -Leaf)))) | Out-Null
    }

    $c2.Child = $in2
    $sp.Children.Add($c2) | Out-Null

    $badd = NovoBotao 'Escolher uma pasta' $Icones.Disco $true $janela
    $badd.HorizontalAlignment = 'Left'
    $badd.Margin = '0,12,0,0'
    $badd.Add_Click({
        $dlg = New-Object Windows.Forms.FolderBrowserDialog
        $dlg.Description = 'Escolha uma pasta do servidor para o Cofre copiar'
        $dlg.ShowNewFolderButton = $false
        if ($dlg.ShowDialog() -ne 'OK') { return }
        $novo = $dlg.SelectedPath
        if ($W.Pastas -notcontains $novo) {
            $W.Pastas = @($W.Pastas) + $novo
            MedirPasta $novo
        }
        Renderizar
    }.GetNewClosure())
    $sp.Children.Add($badd) | Out-Null

    if ($W.Ambiente.VMs.Count -gt 0) {
        $sp.Children.Add((BlocoAviso 'info' (
            "As $($W.Ambiente.VMs.Count) maquina(s) virtual(is) deste host ja estao no calculo acima e " +
            'vao para o Cofre de qualquer forma - nao precisam ser marcadas aqui.'))) | Out-Null
    }

    return $sp
}

<#
    Mede uma pasta.

    Diferente do disco, aqui NAO da para usar o tamanho do volume: e preciso
    somar arquivo por arquivo. Numa pasta grande isso demora e a janela
    congela - entao o cursor vira ampulheta e o Dispatcher desenha isso antes
    de comecar, em vez de a janela simplesmente travar sem explicacao.

    O resultado fica guardado: escolher a mesma pasta de novo nao remede.
#>
function MedirPasta([string]$pasta) {
    if ($W.TamanhoDasPastas.ContainsKey($pasta)) { return }
    $janela.Cursor = [Windows.Input.Cursors]::Wait
    $janela.Dispatcher.Invoke([action]{}, [Windows.Threading.DispatcherPriority]::Render)
    $total = 0
    try {
        foreach ($f in @(Get-ChildItem $pasta -Recurse -File -Force -ErrorAction SilentlyContinue)) {
            $total += $f.Length
        }
    } catch { }
    $W.TamanhoDasPastas[$pasta] = $total
    $janela.Cursor = $null
}

function Passo4_Credenciais {
    $sp = New-Object Windows.Controls.StackPanel

    $sp.Children.Add((NovoTexto (
        'Use um usuario IAM criado so para este cartorio, com acesso apenas a este bucket. ' +
        'Assim, se a credencial vazar, o estrago para no backup de um cartorio.') 13 $Cores.Texto2)) | Out-Null

    $esp = New-Object Windows.Controls.Border; $esp.Height = 22
    $sp.Children.Add($esp) | Out-Null

    $c1 = CampoTexto 'Access Key ID' $W.ChaveAws 'Comeca com AKIA'
    $sp.Children.Add($c1.Elemento) | Out-Null
    $W.Caixas['chaveAws'] = $c1.Caixa

    # Campo de senha: nao aparece na tela e nao entra em print.
    $c2 = CampoTexto 'Secret Access Key' $W.SegredoAws 'Aparece uma unica vez na AWS, na criacao da chave' $true
    $sp.Children.Add($c2.Elemento) | Out-Null
    $W.Caixas['segredoAws'] = $c2.Caixa

    <#
        A mesma credencial serve para os dois modos.

        Neste servidor ela ENVIA. No computador do gerente, a mesma
        credencial LE os estados de todos os cartorios - e por isso o modo
        gerente nao precisa de servidor, dominio nem token: quem tem a chave
        do bucket ve o parque inteiro.

        Se o cartorio nao deve enxergar os outros, use uma credencial
        restrita ao prefixo dele. A tela "Todos os cartorios" simplesmente
        mostraria so ele - sem erro, sem quebrar nada.

        NO CARTORIO ESTE TEXTO NAO APARECE. Quem instala num cartorio nao tem
        por que saber que existe um modo gerente, nem que existem outros
        cartorios no mesmo bucket.
    #>
    if ((ModoDoPrograma $raiz) -eq 'gerente') {
        $sp.Children.Add((BlocoAviso 'info' (
            'Esta mesma credencial serve para o modo gerente: instalado no seu computador, ' +
            'o CH.Com Cofre le os estados de todos os cartorios direto do bucket, na tela ' +
            '"Todos os cartorios". Nao ha servidor, dominio nem token no meio.'))) | Out-Null
    }

    $sp.Children.Add((Secao 'Permissoes que esse usuario precisa ter' '')) | Out-Null
    $c = NovoCartao
    $inner = New-Object Windows.Controls.StackPanel
    foreach ($p in @(
        @{ N = 's3:ListBucket';    D = 'ver o que ja existe no Cofre' }
        @{ N = 's3:PutObject';     D = 'enviar as copias' }
        @{ N = 's3:GetObject';     D = 'trazer de volta na restauracao' }
        @{ N = 's3:RestoreObject'; D = 'DESCONGELAR do Deep Archive - sem isso o backup sobe e nunca volta' }
        @{ N = 'NAO precisa de s3:DeleteObject'; D = 'o agente nunca apaga nada na nuvem - e a credencial roubada tambem nao' }
    )) {
        $cor = if ($p.N -eq 's3:RestoreObject') { 'aviso' } else { 'ok' }
        $inner.Children.Add((LinhaItem 'outro' $p.N $p.D $cor '' '')) | Out-Null
    }
    $c.Child = $inner
    $sp.Children.Add($c) | Out-Null

    return $sp
}

<#
    O passo que nao da para pular.

    O botao Avancar so habilita depois que a pessoa marca a caixa. E a caixa
    so aparece depois que ela salva ou imprime o papel da chave.

    Isso e proposital e nao e burocracia: se a chave existir so neste servidor
    e este servidor for destruido - o cenario exato para o qual o Cofre existe
    - o backup na AWS vira lixo irrecuperavel.
#>
function Passo5_Chave {
    $sp = New-Object Windows.Controls.StackPanel

    if (-not $W.Chave) { $W.Chave = GerarChave }

    $sp.Children.Add((BlocoAviso 'perigo' (
        'SEM A CHAVE, O QUE ESTA NA AWS E LIXO IRRECUPERAVEL. Nem a CH.Com, nem a Amazon, ' +
        'nem quem tiver a senha da conta consegue ler. Se ela existir so neste servidor e ' +
        'este servidor for destruido, o backup morre junto. Nao ha suporte que resolva.'))) | Out-Null

    $sp.Children.Add((Secao 'Guarde a chave em tres lugares' 'E um deles precisa ser fora do cartorio')) | Out-Null

    $c = NovoCartao
    $inner = New-Object Windows.Controls.StackPanel
    foreach ($l in @(
        @{ T = 'Neste servidor';               D = 'o Cofre grava sozinho, com acesso so para administradores' }
        @{ T = 'No cofre de senhas da CH.Com'; D = 'fora da cidade, se possivel' }
        @{ T = 'Em papel, envelope lacrado';   D = 'salve o arquivo abaixo, imprima, e apague o arquivo' }
    )) {
        $inner.Children.Add((LinhaItem 'outro' $l.T $l.D 'aviso' '' '')) | Out-Null
    }
    $c.Child = $inner
    $sp.Children.Add($c) | Out-Null

    $bots = New-Object Windows.Controls.StackPanel
    $bots.Orientation = 'Horizontal'
    $bots.Margin = '0,18,0,0'

    $bSalvar = NovoBotao 'Salvar o papel da chave' $Icones.Chave $true $janela
    <#
        Sem nome de cartorio o papel da chave sai sem dono - e
        EscreverPapelDaChave recusa nome vazio, porque o parametro e
        Mandatory. O clique derrubava o assistente INTEIRO, e quem estava
        configurando via a tela sumir bem no passo da chave, que e o unico
        passo que nao da para pular.
    #>
    $bSalvar.IsEnabled = [bool]$W.Cartorio
    $bSalvar.Add_Click({
        $dlg = New-Object Windows.Forms.SaveFileDialog
        $dlg.Filter = 'Texto (*.txt)|*.txt'
        $dlg.FileName = "CHAVE-DO-COFRE-$($W.Cartorio).txt"
        $dlg.Title = 'Salve em local seguro - depois imprima e apague o arquivo'
        if ($dlg.ShowDialog() -ne 'OK') { return }

        EscreverPapelDaChave -Arquivo $dlg.FileName -Chave $W.Chave `
            -Cartorio $W.Cartorio -Maquina $W.Ambiente.Maquina -Bucket $W.Bucket

        <#
            SALVAR E CONFERIR QUE SALVOU.

            A caixa de dialogo pode voltar OK e o arquivo nao existir: pasta
            sem permissao, disco cheio, antivirus. Marcar $W.Guardou sem olhar
            o disco e acreditar no dialogo em vez de acreditar no arquivo.
        #>
        if (-not (Test-Path $dlg.FileName)) {
            Avisar 'Nao consegui gravar o papel da chave nesse lugar. Escolha outra pasta.'
            return
        }
        $W.PapelSalvo = $dlg.FileName

        # Abre o bloco de notas com o papel: sem isso, "salvei" costuma virar
        # um arquivo esquecido numa pasta, nunca lido nem impresso.
        Start-Process notepad.exe -ArgumentList $dlg.FileName
        $W.Guardou = $true
        Renderizar
    }.GetNewClosure())
    $bots.Children.Add($bSalvar) | Out-Null
    $sp.Children.Add($bots) | Out-Null

    <#
        MARCAR NAO E GUARDAR.

        A confirmacao era uma caixa de selecao: "confirmo que guardei a chave".
        Um clique. A pessoa com pressa marca sem ter salvo nada, e o assistente
        deixa passar.

        E o que essa caixinha protegia era isto: sem a chave, o que esta na AWS
        e lixo cifrado. Nem a CH.Com, nem a Amazon, nem o dono da conta le. Se
        ela existir so no servidor que ela protege, e o servidor for destruido
        - que e exatamente o cenario para o qual o Cofre existe - o backup
        morre junto.

        Uma caixinha de selecao nao pode ser a unica coisa entre 38 cartorios e
        isso.

        Agora sao duas provas, e as duas sao verificaveis:

          1. O ARQUIVO EXISTE. Conferido no disco depois de gravar, e nao pelo
             retorno do dialogo.
          2. A PESSOA LEU O PAPEL. Ela digita de volta os ultimos seis
             caracteres da chave. Nao da para adivinhar, e nao da para
             responder sem abrir o arquivo que acabou de salvar.

        E o mesmo mecanismo que carteira de criptomoeda usa para a frase de
        recuperacao, pelo mesmo motivo: o custo de errar e total e irreversivel.
    #>
    if ($W.Guardou) {
        $ultimos = $W.Chave.Conteudo.Substring($W.Chave.Conteudo.Length - 6)

        $sp.Children.Add((Secao 'Confirme que o papel esta com voce' `
            'Abra o arquivo que acabou de salvar e copie o final da chave de conteudo')) | Out-Null

        $c = CampoTexto 'Ultimos 6 caracteres da chave de conteudo' '' 'esta no papel, na linha CHAVE DE CONTEUDO'
        $sp.Children.Add($c.Elemento) | Out-Null
        $W.Caixas['confChave'] = $c.Caixa

        $aviso = NovoTexto ('Guardado em: ' + $W.PapelSalvo) 12 $Cores.Texto3
        $aviso.Margin = '0,10,0,0'
        $sp.Children.Add($aviso) | Out-Null

        $resposta = NovoTexto '' 13 $Cores.Vermelho 'SemiBold'
        $resposta.Margin = '0,10,0,0'
        $sp.Children.Add($resposta) | Out-Null

        $c.Caixa.Add_TextChanged({
            $digitado = $c.Caixa.Text.Trim()
            if (-not $digitado) { $resposta.Text = ''; $btnAvancar.IsEnabled = $false; return }
            if ($digitado -ceq $ultimos) {
                $resposta.Foreground = Pincel $Cores.Verde
                $resposta.Text = 'Confere. O papel esta com voce.'
                $btnAvancar.IsEnabled = $true
            } else {
                $resposta.Foreground = Pincel $Cores.Vermelho
                $resposta.Text = 'Nao confere ainda. Olhe o papel que voce salvou.'
                $btnAvancar.IsEnabled = $false
            }
        }.GetNewClosure())

    } else {
        $sp.Children.Add((BlocoAviso 'aviso' 'Salve o papel da chave para poder continuar.')) | Out-Null
    }

    return $sp
}

<#
    Testar de verdade contra a AWS.

    Sobe 8 MB, confere que chegou, e apaga. Descobrir aqui que a credencial
    esta errada, que o bucket nao existe ou que falta permissao e barato;
    descobrir na primeira madrugada, nao.

    De quebra, mede a velocidade REAL - que e o numero que decide se subir VM
    por este link e viavel.
#>

<#
    O aviso do bucket desprotegido.

    Aparece nos DOIS modos, porque o risco e o mesmo: o agente nao pode
    apagar - a politica nao concede s3:DeleteObject - mas isso protege contra
    a credencial roubada, nao contra quem entra no console da AWS.

    E deliberadamente um aviso, e nao uma trava. Um cartorio sem Bloqueio de
    Objeto ainda esta muito melhor com backup do que sem. Impedir a
    configuracao aqui trocaria um risco por um pior.
#>
function BlocoProtecaoDoBucket($protecao) {
    if (-not $protecao) { return $null }

    if ($protecao.Erro) {
        return (BlocoAviso 'aviso' (
            'Nao consegui conferir se o bucket tem Bloqueio de Objeto: ' + $protecao.Erro +
            ' Confira no console da AWS - sem ele, quem entrar na conta apaga o backup.'))
    }
    if (-not $protecao.Versionado) {
        return (BlocoAviso 'perigo' (
            'ESTE BUCKET NAO TEM BLOQUEIO DE OBJETO. ' + $protecao.Texto + '. ' +
            'O agente nao pode apagar nada - a politica dele nao tem s3:DeleteObject - mas ' +
            'quem entrar no console da AWS apaga o backup inteiro, e o ransomware moderno faz ' +
            'exatamente isso antes de cifrar o servidor. Ligue versionamento e Bloqueio de ' +
            'Objeto em modo Governanca, 180 dias: e o minimo que o Deep Archive ja cobra, ' +
            'entao nao custa nada a mais. O passo a passo esta em aws/COMECAR-NA-AWS.md.'))
    }
    return (BlocoAviso 'info' (
        'O bucket tem versionamento ligado, que e o que o Bloqueio de Objeto exige. ' +
        'Daqui nao da para confirmar se o Bloqueio esta ativo - o rclone nao le essa ' +
        'configuracao. Confira uma vez no console da AWS.'))
}

function Passo6_Teste {
    $sp = New-Object Windows.Controls.StackPanel
    $ehGerente = ((ModoDoPrograma $raiz) -eq 'gerente')

    if (-not $W.Testou) {
        if ($ehGerente) {
            $sp.Children.Add((FaixaVeredito 'info' 'Vamos testar a leitura do Cofre' `
                'O programa lista o bucket e conta quantos cartorios ja publicaram estado.')) | Out-Null
            $sp.Children.Add((NovoTexto (
                'Nada e escrito. A credencial do gerente e so de leitura, e e assim que deve ser: ' +
                'a maquina que enxerga os 38 cartorios nao precisa poder escrever em nenhum deles.') `
                13 $Cores.Texto2)) | Out-Null
        } else {
            $sp.Children.Add((FaixaVeredito 'info' 'Vamos testar a conexao' `
                'O Cofre sobe uma sonda de 8 MB para o bucket e confere que ela chegou inteira.')) | Out-Null
            $sp.Children.Add((NovoTexto 'Isso leva de alguns segundos a alguns minutos, conforme o link.' `
                13 $Cores.Texto2)) | Out-Null
        }
        return $sp
    }

    if ($W.Erro) {
        $sp.Children.Add((FaixaVeredito 'erro' 'O teste nao passou' $W.Erro)) | Out-Null
        $dica = if ($ehGerente) {
            'Confira a Access Key, a Secret, o nome do bucket e a regiao. O usuario IAM do ' +
            'gerente precisa de s3:ListBucket e s3:GetObject no bucket inteiro. Nao precisa ' +
            'de s3:PutObject: o computador do gerente nunca escreve no Cofre de ninguem.'
        } else {
            'Confira a Access Key, a Secret, o nome do bucket e a regiao. O usuario IAM ' +
            'precisa de s3:PutObject, s3:GetObject, s3:ListBucket e s3:RestoreObject. ' +
            'Nao precisa de s3:DeleteObject: o agente nunca apaga nada na nuvem.'
        }
        $sp.Children.Add((BlocoAviso 'aviso' $dica)) | Out-Null
        return $sp
    }

    if ($ehGerente) {
        $quantos = [int]$W.Cartorios
        $frase = if ($quantos -eq 0) {
            'O bucket respondeu, mas ainda nao ha cartorio nenhum publicando estado. ' +
            'Isso e o esperado antes do primeiro backup - a tela "Todos os cartorios" ' +
            'vai se preencher sozinha conforme os cartorios forem instalados.'
        } elseif ($quantos -eq 1) {
            '1 cartorio ja publica estado neste bucket.'
        } else {
            "$quantos cartorios ja publicam estado neste bucket."
        }
        $sp.Children.Add((FaixaVeredito 'ok' 'Leitura do Cofre funcionando' $frase)) | Out-Null
        $bp = BlocoProtecaoDoBucket $W.Protecao
        if ($bp) { $sp.Children.Add($bp) | Out-Null }
        return $sp
    }

    $sp.Children.Add((FaixaVeredito 'ok' 'Conexao com a AWS funcionando' `
        "Subida medida: $($W.Mbps) Mbps")) | Out-Null
        $bp = BlocoProtecaoDoBucket $W.Protecao
        if ($bp) { $sp.Children.Add($bp) | Out-Null }

    # A conta que decide se a arquitetura serve NESTE cartorio.
    $totalVM = 0
    foreach ($v in $W.Ambiente.VMs) { $totalVM += $v.TamanhoBytes }
    if ($totalVM -gt 0 -and $W.Mbps -gt 0) {
        $horas = [math]::Round((($totalVM * 0.5) * 8) / ($W.Mbps * 1MB) / 3600, 1)
        $c = NovoCartao
        $inner = New-Object Windows.Controls.StackPanel
        $inner.Children.Add((LinhaInfo 'VMs somadas' (Tamanho $totalVM))) | Out-Null
        $inner.Children.Add((LinhaInfo 'Estimando 50% de compressao' (Tamanho ($totalVM * 0.5)))) | Out-Null
        $inner.Children.Add((LinhaInfo 'Uma rodada completa' "cerca de $horas horas")) | Out-Null
        $c.Child = $inner
        $sp.Children.Add($c) | Out-Null

        if ($horas -le 8) {
            $sp.Children.Add((BlocoAviso 'info' 'Cabe numa janela noturna. Envio mensal sem aperto.')) | Out-Null
        } elseif ($horas -le 48) {
            $sp.Children.Add((BlocoAviso 'aviso' 'Nao cabe numa noite. A rodada mensal vai ocupar o fim de semana.')) | Out-Null
        } else {
            $sp.Children.Add((BlocoAviso 'perigo' (
                "Uma rodada completa levaria cerca de $horas horas neste link. Considere " +
                'proteger so os bancos aqui, ou levar a carga inicial em disco fisico.'))) | Out-Null
        }
    }

    return $sp
}

function Passo7_Pronto {
    $sp = New-Object Windows.Controls.StackPanel
    $ag = $W.Agendamento
    $ehGerente = ((ModoDoPrograma $raiz) -eq 'gerente')

    <#
        O veredito sai do que ACONTECEU, e nao do que se pretendia.

        A tela dizia "vai rodar sozinho a partir de agora" antes de o
        agendamento ter sido tentado. Se ele falhasse - sem permissao, politica
        de dominio, servico do Agendador parado - a ultima coisa que a pessoa
        via era a promessa, e o backup nunca rodava.
    #>
    if ($ehGerente) {
        $sp.Children.Add((FaixaVeredito 'ok' 'Tudo pronto' `
            'Este computador ja le o Cofre. Abra "Todos os cartorios" para ver o parque.')) | Out-Null
    } elseif ($ag -and $ag.Agendou) {
        $sp.Children.Add((FaixaVeredito 'ok' 'Tudo pronto' `
            'O Cofre esta configurado e agendado. A partir de hoje ele roda sozinho, com o programa fechado.')) | Out-Null
    } else {
        $motivo = if ($ag -and $ag.Erro) { $ag.Erro } else { 'motivo desconhecido' }
        $sp.Children.Add((FaixaVeredito 'erro' 'Configurado, mas NAO vai rodar sozinho' (
            'O destino esta certo e o teste passou - mas nao consegui registrar as tarefas no ' +
            'Agendador do Windows: ' + $motivo))) | Out-Null
        $sp.Children.Add((BlocoAviso 'perigo' (
            'Enquanto isso nao for resolvido, o backup so acontece se alguem abrir o programa ' +
            'e clicar em "Executar agora". Rode o programa como Administrador e configure de ' +
            'novo, ou registre as tarefas a mao no Agendador de Tarefas.'))) | Out-Null
    }

    $sp.Children.Add((Secao 'O que foi configurado' '')) | Out-Null
    $c = NovoCartao
    $inner = New-Object Windows.Controls.StackPanel
    $inner.Children.Add((LinhaInfo 'Cartorio'         $W.Cartorio)) | Out-Null
    $inner.Children.Add((LinhaInfo 'Destino'          "$($W.Bucket) ($($W.Regiao))")) | Out-Null
    $inner.Children.Add((LinhaInfo 'Classe'           'DEEP_ARCHIVE, gravada no envio')) | Out-Null
    $inner.Children.Add((LinhaInfo 'Area de trabalho' $W.Trabalho)) | Out-Null
    $inner.Children.Add((LinhaInfo 'Criptografia'     'AES-256 neste servidor' $Cores.Verde)) | Out-Null
    $inner.Children.Add((LinhaInfo 'Discos inteiros' `
        $(if ($W.Discos.Count -gt 0) { ($W.Discos -join ', ') } else { 'nenhum' }))) | Out-Null
    $inner.Children.Add((LinhaInfo 'Pastas do cartorio' `
        $(if ($W.Pastas.Count -gt 0) { "$($W.Pastas.Count) pasta(s), todo dia" } else { 'nenhuma escolhida' }))) | Out-Null
    $inner.Children.Add((LinhaInfo 'Bancos'           'todo dia, 01:30')) | Out-Null
    $inner.Children.Add((LinhaInfo 'VMs e imagem'     'a cada 4 semanas, sabado 22:00')) | Out-Null
    $c.Child = $inner
    $sp.Children.Add($c) | Out-Null

    <#
        A PRIMEIRA COPIA COMECA AQUI, E NAO NA PROXIMA MADRUGADA.

        O assistente terminava agendando e mandando embora. Quem instala num
        cartorio vai embora de la sem nunca ter visto uma copia acontecer - e
        descobre semanas depois, se descobrir, que alguma coisa no caminho nao
        funcionava.

        Pior: o servidor passa dias "configurado" e sem nenhuma copia. O
        agendamento so roda a 01:30, e o tecnico ja foi.

        O botao dispara a rodada COMPLETA - -Tudo, o mesmo modo da tarefa
        mensal: maquinas virtuais, imagem do servidor, discos, pastas e
        bancos. Nao e uma amostra.

        Ele nao trava a janela: o motor sobe em processo separado e o painel
        acompanha pelo estado. Fechar aqui nao interrompe nada.
    #>
    if ((ModoDoPrograma $raiz) -ne 'gerente') {
        $sp.Children.Add((Secao 'A primeira copia' 'Nao espere a madrugada para saber se funciona')) | Out-Null

        $cA = NovoCartao
        $inA = New-Object Windows.Controls.StackPanel
        $inA.Children.Add((NovoTexto (
            'O agendamento so roda a 01:30. Rodar a primeira copia agora e a unica forma de ' +
            'sair daqui sabendo que funciona - e nao achando que funciona.') 13 $Cores.Texto2)) | Out-Null

        $bAgora = NovoBotao 'Fazer o backup completo agora' $Icones.Play $true $janela
        $bAgora.HorizontalAlignment = 'Left'
        $bAgora.Margin = '0,16,0,0'
        $bAgora.Add_Click({
            $bAgora.IsEnabled = $false
            $bAgora.Content = 'iniciado - acompanhe no Painel'
            <#
                ELEVADO, porque o motor exporta VM, chama o wbadmin e cria
                copia de sombra. Sem isso ele falharia em silencio.
            #>
            try {
                Start-Process powershell -Verb RunAs -ArgumentList @(
                    '-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden',
                    '-File', (Aspas (CaminhoDe $raiz 'cofre.ps1')), '-Tudo')
            } catch {
                $bAgora.IsEnabled = $true
                $bAgora.Content = 'Fazer o backup completo agora'
                Avisar 'O Windows precisa de permissao de administrador para fazer a copia. Nada foi feito.'
            }
        }.GetNewClosure())
        $inA.Children.Add($bAgora) | Out-Null

        $inA.Children.Add((NovoTexto (
            'Feche esta janela depois de clicar. A copia continua sozinha, e o Painel mostra o ' +
            'andamento - inclusive se voce reabrir o programa mais tarde.') 12 $Cores.Texto3)) | Out-Null

        $cA.Child = $inA
        $sp.Children.Add($cA) | Out-Null
    }

    $sp.Children.Add((BlocoAviso 'aviso' (
        'ANTES DE SAIR DO CARTORIO: confirme que o arquivo da chave nao ficou neste servidor. ' +
        'Ele deve estar impresso e no seu cofre de senhas, e o arquivo apagado daqui.'))) | Out-Null

    return $sp
}

# ==============================================================================
#  Navegacao
# ==============================================================================
<#
    O GERENTE NAO E UM CARTORIO, E NAO DEVE RESPONDER COMO UM.

    O assistente tinha sete passos fixos, todos escritos para quem esta
    instalando NUM CARTORIO: escolha os discos, escolha as pastas, guarde a
    chave, agende a madrugada.

    No computador do gerente isso e pior que inutil - e errado:

    - Ele nao copia nada. Nao tem disco nem pasta para escolher.
    - Ele nao gera chave. A chave dele nao decifra cartorio nenhum, entao
      mandar guardar essa chave "senao o backup morre" seria mentira.
    - A credencial dele e SO DE LEITURA. O teste que sobe 8 MB falharia por
      falta de permissao - num acesso perfeitamente correto.

    Entao cada modo tem a sua lista de passos, e a numeracao ("3 de 5") sai
    dela, nao de um total fixo.
#>
$PASSOS_CARTORIO = @('Bemvindo','Destino','Origem','Credenciais','Chave','Teste','Pronto')
$PASSOS_GERENTE  = @('Bemvindo','Destino','Credenciais','Teste','Pronto')

$W.Passos = if ((ModoDoPrograma $raiz) -eq 'gerente') { $PASSOS_GERENTE } else { $PASSOS_CARTORIO }
$W.Total = $W.Passos.Count

function NomeDoPasso([int]$n) {
    if ($n -lt 1 -or $n -gt $W.Passos.Count) { return '' }
    return $W.Passos[$n - 1]
}

$titulos = @{
    'Bemvindo'    = @{ T = 'Bem-vindo';             S = 'O que o Cofre encontrou neste servidor' }
    'Destino'     = @{ T = 'Destino na nuvem';      S = 'Onde as copias vao ficar' }
    'Origem'      = @{ T = 'Origem';                S = 'O que vai para o Cofre, e quanto tempo leva' }
    'Credenciais' = @{ T = 'Credenciais da AWS';    S = 'Acesso ao bucket' }
    'Chave'       = @{ T = 'Chave de criptografia'; S = 'O passo mais importante de todos' }
    'Teste'       = @{ T = 'Teste';                 S = 'Conferindo que funciona de verdade' }
    'Pronto'      = @{ T = 'Pronto';                S = 'Configuracao concluida' }
}

function Renderizar {
    $area.Children.Clear()
    $passo = NomeDoPasso $W.Passo
    $ultimo = ($W.Passo -eq $W.Total)

    $janela.FindName('txtEtapa').Text = $titulos[$passo].T
    $janela.FindName('txtSubEtapa').Text = $titulos[$passo].S
    $janela.FindName('txtPasso').Text = "$($W.Passo) de $($W.Total)"
    $janela.FindName('barra').Maximum = $W.Total
    $janela.FindName('barra').Value = $W.Passo

    # Comparado pelo NOME do passo, e nao pelo numero: no modo gerente o
    # "Teste" e o passo 4, e o numero 5 nem existe.
    $btnVoltar.Visibility = if ($W.Passo -eq 1 -or $ultimo) { 'Hidden' } else { 'Visible' }
    $btnCancelar.Visibility = if ($ultimo) { 'Hidden' } else { 'Visible' }
    $btnAvancar.Content = switch ($passo) {
        'Teste'  { if ($W.Testou -and -not $W.Erro) { 'Avancar' } else { 'Testar agora' } }
        'Pronto' { 'Concluir' }
        default  { 'Avancar' }
    }
    $btnAvancar.IsEnabled = $true

    $elemento = switch ($passo) {
        'Bemvindo'    { Passo1_Bemvindo }
        'Destino'     { Passo2_Destino }
        'Origem'      { Passo3_Origem }
        'Credenciais' { Passo4_Credenciais }
        'Chave'       { Passo5_Chave }
        'Teste'       { Passo6_Teste }
        'Pronto'      { Passo7_Pronto }
    }
    $area.Children.Add($elemento) | Out-Null

    # No passo da chave, Avancar so libera com a caixa marcada.
    if ((NomeDoPasso $W.Passo) -eq 'Chave') { $btnAvancar.IsEnabled = $false }
}

<#
    Valida o passo antes de deixar avancar.

    Devolve texto quando ha problema, vazio quando esta tudo certo. Deixar
    passar um bucket vazio aqui significa descobrir isso la no teste, com a
    pessoa ja tendo digitado a credencial - retrabalho a toa.
#>
function ProblemaDoPasso {
    switch (NomeDoPasso $W.Passo) {
        'Bemvindo' {
            <#
                O passo 1 NAO bloqueia, mesmo sem nada detectado.

                Isto era uma trava circular, pega instalando o Cofre dentro de
                uma VM limpa: o passo 1 recusava avancar com "nada a proteger",
                mas as PASTAS e os DISCOS - que sao o que aquela VM tem - so
                sao escolhidos no passo 3. Nao havia como chegar la para
                escolher.

                A deteccao acha VM, banco e imagem de sistema. Pasta e disco
                ninguem detecta: sao escolha de quem conhece o cartorio. Entao
                "nada detectado" no passo 1 e informacao, nao impedimento.

                A recusa de verdade acontece no passo 3, depois de a pessoa ter
                tido a chance de escolher.
            #>
        }
        3 {
            $temAlgo = ($W.Plano.Tarefas.Count -gt 0) -or
                       ($W.Discos.Count -gt 0) -or ($W.Pastas.Count -gt 0)
            if (-not $temAlgo) {
                return ('Nao ha nada para o Cofre proteger neste servidor. ' +
                        'Escolha ao menos um disco ou uma pasta acima.')
            }
        }
        'Destino' {
            $W.Cartorio = ($W.Caixas['cartorio'].Text -replace '[^A-Za-z0-9\-_]', '-').ToLower().Trim('-')
            $W.Bucket = $W.Caixas['bucket'].Text.Trim()
            $W.Regiao = $W.Caixas['regiao'].Text.Trim()
            if (-not $W.Cartorio) { return 'Informe o nome curto do cartorio.' }
            if (-not $W.Bucket)   { return 'Informe o bucket na AWS.' }
            if (-not $W.Regiao)   { return 'Informe a regiao.' }
            if (-not $W.Trabalho) { return 'Nenhum disco local tem espaco para a area de trabalho.' }
        }
        'Credenciais' {
            $W.ChaveAws = $W.Caixas['chaveAws'].Text.Trim()
            $W.SegredoAws = $W.Caixas['segredoAws'].Password
            if (-not $W.ChaveAws)   { return 'Informe a Access Key ID.' }
            if (-not $W.SegredoAws) { return 'Informe a Secret Access Key.' }
        }
    }
    return ''
}

function Avisar([string]$texto) {
    [Windows.MessageBox]::Show($texto, 'CH.Com Cofre', 'OK', 'Warning') | Out-Null
}

<#
    O teste de verdade contra a AWS.

    Escreve o rclone.conf, sobe 8 MB, confere, apaga e mede.

    A janela CONGELA durante isso, e nao ha como evitar sem complicar muito:
    PowerShell roda a interface numa linha de execucao so. Entao, em vez de
    fingir que nao congela, o botao muda para "testando..." e o cursor vira
    ampulheta ANTES de comecar - o Dispatcher e chamado de proposito para
    desenhar isso antes de bloquear.

    E aceitavel porque acontece uma vez, na instalacao, com alguem na frente.
    O backup de verdade nunca roda dentro da janela.
#>
function ExecutarTeste {
    $btnAvancar.Content = 'testando...'
    $btnAvancar.IsEnabled = $false
    $btnVoltar.IsEnabled = $false
    $janela.Cursor = [Windows.Input.Cursors]::Wait
    # Forca o desenho antes de bloquear a linha de execucao.
    $janela.Dispatcher.Invoke([action]{}, [Windows.Threading.DispatcherPriority]::Render)

    $W.Erro = ''
    $W.Mbps = 0
    $pastaTeste = CaminhoDe $env:TEMP 'cofre-teste'

    try {
        $rclone = CaminhoDoRclone $raiz
        if (-not $rclone) { throw 'o rclone nao esta instalado nesta pasta.' }

        EscreverRcloneConf -Rclone $rclone -Arquivo (CaminhoDe $dados 'rclone.conf') `
            -ChaveAws $W.ChaveAws -SegredoAws $W.SegredoAws -Regiao $W.Regiao `
            -Bucket $W.Bucket -Chave $W.Chave

        <#
            NO MODO GERENTE, O TESTE E LER - NAO ESCREVER.

            A credencial do gerente e so de leitura, de proposito: a maquina
            que enxerga os 38 cartorios nao precisa poder escrever em nenhum
            deles. Subir a sonda de 8 MB falharia por falta de permissao num
            acesso perfeitamente correto, e mandaria o gerente conceder
            PutObject "para o teste passar" - abrindo o parque inteiro para a
            maquina que menos precisa disso.

            Entao aqui o teste e o que ele realmente vai fazer todo dia: listar
            o bucket.
        #>
        if ((ModoDoPrograma $raiz) -eq 'gerente') {
            $relogio = [Diagnostics.Stopwatch]::StartNew()
            $exec = RodarRclone -Rclone $rclone -Argumentos @(
                'lsjson', "cofre-s3:$($W.Bucket)", '--config', (CaminhoDe $dados 'rclone.conf'),
                '--max-depth', '1')
            $relogio.Stop()
            if ($exec.Codigo -ne 0) { throw $exec.Erro }
            $itens = LerListaDoRclone $exec.Saida
            $W.Cartorios = @($itens | Where-Object { $_.IsDir }).Count
            $W.Protecao = ConferirProtecaoDoBucket -Rclone $rclone `
                -Config (CaminhoDe $dados 'rclone.conf') -Bucket $W.Bucket
            $W.Mbps = 0
            $W.Testou = $true
            return
        }

        <#
            A SONDA MEDIA O PIOR CASO POSSIVEL.

            Era UM arquivo de 8 MB, com pedaco de 64 MB - ou seja, nunca virava
            envio em partes, nunca teve paralelismo nenhum. Alem disso, os
            poucos segundos de partida do rclone, aperto de mao TLS e descoberta
            da regiao entravam inteiros na conta.

            Resultado num cartorio: 10,6 Mbps medidos, num link capaz de mais.
            E esse numero errado ia direto para a estimativa de quantas horas
            leva o backup - que e o numero que se promete ao cliente.

            Agora sao QUATRO arquivos de 8 MB, subindo do mesmo jeito que o
            motor sobe de verdade. A partida fica diluida em quatro vezes mais
            dados, e o que se mede passa a ser o que vai acontecer de noite.
        #>
        if (Test-Path $pastaTeste) { Remove-Item $pastaTeste -Recurse -Force }
        New-Item -ItemType Directory -Path $pastaTeste -Force | Out-Null
        $bloco = New-Object byte[] (8MB)
        (New-Object Random).NextBytes($bloco)
        for ($i = 1; $i -le 4; $i++) {
            [System.IO.File]::WriteAllBytes((CaminhoDe $pastaTeste "teste-de-conexao-$i.bin"), $bloco)
        }

        <#
            CAMINHO FIXO, E NADA DE APAGAR.

            A versao anterior subia para uma pasta com carimbo de hora e
            depois dava purge. Isso obrigava a credencial do cartorio a ter
            s3:DeleteObject - exatamente o poder que nao se pode dar a um
            servidor que pode ser invadido.

            O roteiro do ransomware atual e: entra no servidor, acha a
            credencial, APAGA O BACKUP NA NUVEM, e so entao cifra a maquina.
            Se o agente nunca precisa apagar, a permissao nunca e concedida, e
            esse roteiro nao tem como terminar.

            Entao a sonda vai sempre para o MESMO caminho: testar de novo
            sobrescreve, em vez de acumular. Sao 8 MB por cartorio, em
            STANDARD - menos de um centavo por mes no parque inteiro.
        #>
        $alvo = "$($W.Cartorio)/_teste"
        $relogio = [Diagnostics.Stopwatch]::StartNew()
        $envio = EnviarPasta -Rclone $rclone -Config (CaminhoDe $dados 'rclone.conf') `
            -Origem $pastaTeste -DestinoRemoto "cofre:$alvo" -ClasseArmazenamento 'STANDARD'
        $relogio.Stop()
        if (-not $envio.Sucesso) { throw $envio.Erro }

        $conf = ConferirEnvio -Rclone $rclone -Config (CaminhoDe $dados 'rclone.conf') `
            -DestinoRemoto "cofre:$alvo" -BytesEsperados 32MB
        if (-not $conf.Confere) { throw "o arquivo nao chegou inteiro: $($conf.Erro)" }
        $W.Mbps = [math]::Round((32MB * 8) / $relogio.Elapsed.TotalSeconds / 1MB, 1)

        # De carona no teste, enquanto a credencial ja esta na mao: o bucket
        # protege contra quem apaga? Ver ConferirProtecaoDoBucket.
        $W.Protecao = ConferirProtecaoDoBucket -Rclone $rclone `
            -Config (CaminhoDe $dados 'rclone.conf') -Bucket $W.Bucket

    } catch {
        $W.Erro = $_.Exception.Message
        # Configuracao que nao passou no teste nao pode ficar no disco: o
        # agendamento comecaria a rodar apontando para um destino que nao
        # funciona, e falharia toda noite em silencio.
        Remove-Item (CaminhoDe $dados 'rclone.conf') -Force -ErrorAction SilentlyContinue
    } finally {
        Remove-Item $pastaTeste -Recurse -Force -ErrorAction SilentlyContinue
        $janela.Cursor = $null
        $btnVoltar.IsEnabled = $true
        $W.Testou = $true
    }
    Renderizar
}

<#
    Grava e agenda ANTES de mostrar a tela final.

    A ordem estava invertida: o passo 7 dizia "tudo pronto, vai rodar sozinho"
    e so DEPOIS, no clique em Concluir, o agendamento acontecia. Se ele
    falhasse, ninguem ficava sabendo - a ultima coisa que a pessoa via era a
    promessa.

    Agora o trabalho acontece na passagem para o ultimo passo, e o ultimo
    passo RELATA. Prometer depois de fazer e diferente de prometer antes.
#>
function GravarTudo {
    $config = NovaConfiguracao
    $config.Cartorio = $W.Cartorio
    $config.Bucket = $W.Bucket
    $config.Regiao = $W.Regiao
    $config.PastaDeTrabalho = $W.Trabalho
    # As pastas escolhidas a mao. Sem esta linha o passo da origem seria
    # decorativo: a pessoa escolheria as pastas e o Cofre nunca saberia delas.
    $config.Pastas = @($W.Pastas)
    $config.Discos = @($W.Discos)
    # A velocidade medida contra a AWS fica guardada: e o que permite a tela
    # de configuracao recalcular o tempo depois, sem medir tudo de novo.
    $config.MbpsMedido = $W.Mbps
    GravarConfiguracao (CaminhoDe $dados 'cofre.conf') $config

    # As credenciais nao ficam em memoria depois de gravadas no rclone.conf.
    $W.SegredoAws = ''
    $W.ChaveAws = ''
    [GC]::Collect()

    <#
        O GERENTE NAO AGENDA NADA.

        No computador dele, agendar criaria uma tarefa que acorda todo dia para
        fazer backup de um servidor que nao existe - falhando em silencio e
        enchendo o Agendador de erro que ninguem vai investigar. Ele so LE o
        parque, e le quando alguem abre o programa.
    #>
    if ((ModoDoPrograma $raiz) -eq 'gerente') {
        $W.Agendamento = [PSCustomObject]@{ Agendou = $true; Erro = $null; Tarefas = @() }
    } else {
        $W.Agendamento = AgendarTarefas
    }
}

function Concluir {
    $janela.DialogResult = $true
    $janela.Close()
}

<#
    Registra as duas tarefas - e DIZ se nao conseguiu.

    Dois defeitos moravam aqui, e juntos explicavam por que "nao tem nada
    concreto":

    1. AS DUAS TAREFAS RODAVAM O MESMO COMANDO.

       cofre.ps1, sem argumento nenhum, nas duas. A diaria - descrita como
       "copia dos bancos" - fazia a rodada COMPLETA: maquinas virtuais e
       imagem do servidor, toda madrugada. Numa VM de 21 GB por um link de 10
       Mbps sao 2,3 horas por noite em vez de por mes, e a conta da AWS na
       mesma proporcao. O motor sempre aceitou -SomenteBancos e -Tudo; era so
       passar.

    2. O ERRO ERA ENGOLIDO.

       catch { } vazio. Sem permissao, com politica de dominio bloqueando, com
       o servico do Agendador parado - o assistente terminava dizendo
       "configuracao concluida" e NADA ficava agendado. O backup nunca rodaria,
       e ninguem descobriria ate precisar restaurar.

       Agora a funcao devolve o que aconteceu, e o passo final mostra.

    E CONFERE DEPOIS DE REGISTRAR

    Register-ScheduledTask pode voltar sem erro e a tarefa nao existir - por
    politica, por antivirus. Perguntar ao Agendador se ela esta la e barato e
    e a diferenca entre "mandei registrar" e "esta registrada".
#>
function AgendarTarefas {
    $r = [PSCustomObject]@{ Agendou = $false; Erro = $null; Tarefas = @() }
    try {
        $base = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' +
                (CaminhoDe $raiz 'cofre.ps1') + '"'

        <#
            DisallowStartIfOnBatteries vem LIGADO por padrao.

            Num servidor de cartorio ligado na tomada isso nunca aparece - ate
            o dia em que o backup e um mini-PC no nobreak, ou o nobreak entra
            em bateria as 3 da manha. A tarefa simplesmente nao roda, e nao
            reclama.
        #>
        $opcoes = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd `
            -ExecutionTimeLimit (New-TimeSpan -Hours 20) -MultipleInstances IgnoreNew `
            -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        $comoSistema = New-ScheduledTaskPrincipal -UserId 'SYSTEM' `
            -LogonType ServiceAccount -RunLevel Highest

        $paraRegistrar = @(
            @{ Nome = 'CH.Com Cofre - diario'
               Arg  = "$base -SomenteBancos"
               Gat  = (New-ScheduledTaskTrigger -Daily -At '01:30')
               Desc = 'Copia externa dos bancos de dados para a AWS' }
            @{ Nome = 'CH.Com Cofre - mensal'
               Arg  = "$base -Tudo"
               Gat  = (New-ScheduledTaskTrigger -Weekly -WeeksInterval 4 -DaysOfWeek Saturday -At '22:00')
               Desc = 'Copia externa completa: maquinas virtuais e imagem do servidor' }
        )

        foreach ($t in $paraRegistrar) {
            $acao = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $t.Arg
            Register-ScheduledTask -TaskName $t.Nome -Action $acao -Trigger $t.Gat `
                -Settings $opcoes -Principal $comoSistema -Description $t.Desc -Force | Out-Null
        }

        foreach ($t in $paraRegistrar) {
            $existe = Get-ScheduledTask -TaskName $t.Nome -ErrorAction SilentlyContinue
            if (-not $existe) { throw "a tarefa '$($t.Nome)' nao ficou registrada no Agendador." }
            $r.Tarefas += $t.Nome
        }
        $r.Agendou = $true

    } catch {
        $r.Erro = $_.Exception.Message
    }
    return $r
}

# --- botoes -------------------------------------------------------------------
$btnAvancar.Add_Click({
    $passo = NomeDoPasso $W.Passo
    if ($passo -eq 'Teste') {
        if (-not $W.Testou -or $W.Erro) { ExecutarTeste; return }
    }
    if ($passo -eq 'Pronto') { Concluir; return }

    $problema = ProblemaDoPasso
    if ($problema) { Avisar $problema; return }

    # Entrar no ultimo passo e o momento de gravar e agendar - assim a tela
    # final relata o que aconteceu, em vez de prometer o que ainda nao houve.
    if ((NomeDoPasso ($W.Passo + 1)) -eq 'Pronto') { GravarTudo }

    $W.Passo++
    Renderizar
})

$btnVoltar.Add_Click({
    if ($W.Passo -le 1) { return }
    $W.Passo--
    # Voltar depois de um teste que falhou tem que permitir testar de novo.
    if ((NomeDoPasso $W.Passo) -ne 'Teste') { $W.Testou = $false; $W.Erro = '' }
    Renderizar
})

$btnCancelar.Add_Click({
    $r = [Windows.MessageBox]::Show(
        'Sair sem configurar? O Cofre nao vai proteger nada ate ser configurado.',
        'CH.Com Cofre', 'YesNo', 'Warning')
    if ($r -eq 'Yes') { $janela.DialogResult = $false; $janela.Close() }
})

# --- abrir --------------------------------------------------------------------
$W.Ambiente = DescobrirAmbiente
$W.Plano = MontarPlano $W.Ambiente
Renderizar

if (-not $NaoAbrir) { $janela.ShowDialog() | Out-Null }
