<#
================================================================================
  CH.Com Cofre - pecas visuais

  Tudo aqui e montado em codigo, e nao em XAML, por um motivo: o conteudo
  depende do que o agente encontrar no servidor. Numero de VMs, de bancos, de
  discos - nada disso e conhecido antes de rodar. Um XAML fixo teria que
  esconder e mostrar dezenas de elementos, o que fica pior de ler e de mudar.

  As cores tem significado fixo no sistema inteiro:
     verde    esta certo
     amarelo  funciona, mas alguem precisa olhar
     vermelho nao esta protegido
     cinza    fora do Cofre de proposito - nao e problema
================================================================================
#>

$Cores = @{
    Fundo      = '#0B0F14'
    Painel     = '#0F141B'
    Cartao     = '#141B24'
    CartaoAlto = '#1A222D'
    Borda      = '#212B37'
    Azul       = '#1E90FF'
    Texto      = '#EAF1F8'
    Texto2     = '#93A2B3'
    Texto3     = '#5D6C7D'
    Verde      = '#2ECC71'
    Amarelo    = '#F0A62E'
    Vermelho   = '#FF4D5A'
    VerdeFundo = '#132A1C'
    AmareloFundo = '#2E2412'
    VermelhoFundo = '#2E1519'
    AzulFundo  = '#16283D'
}

# Icones da fonte Segoe MDL2 Assets, que ja vem no Windows 10 e 11.
# Usar fonte em vez de imagem: nada para empacotar, escala sem borrar, e
# muda de cor como texto.
$Icones = @{
    Escudo    = [char]0xE72E
    Nuvem     = [char]0xE753
    Servidor  = [char]0xE977
    Banco     = [char]0xE968
    Disco     = [char]0xEDA2
    Certo     = [char]0xE73E
    Alerta    = [char]0xE7BA
    Erro      = [char]0xEA39
    Relogio   = [char]0xE917
    Play      = [char]0xE768
    Chave     = [char]0xE192
    Grafico   = [char]0xE9D2
    Maquina   = [char]0xE7F4
    Baixar    = [char]0xE896
    Info      = [char]0xE946
}

function Pincel([string]$hex) {
    return (New-Object Windows.Media.SolidColorBrush(
        [Windows.Media.ColorConverter]::ConvertFromString($hex)))
}

function NovoTexto([string]$texto, [double]$tamanho, [string]$cor, [string]$peso = 'Normal') {
    $t = New-Object Windows.Controls.TextBlock
    $t.Text = $texto
    $t.FontSize = $tamanho
    $t.Foreground = Pincel $cor
    $t.FontWeight = $peso
    $t.TextWrapping = 'Wrap'
    return $t
}

function NovoIcone([char]$glifo, [double]$tamanho, [string]$cor) {
    $t = New-Object Windows.Controls.TextBlock
    $t.Text = [string]$glifo
    $t.FontFamily = New-Object Windows.Media.FontFamily('Segoe MDL2 Assets')
    $t.FontSize = $tamanho
    $t.Foreground = Pincel $cor
    $t.VerticalAlignment = 'Center'
    return $t
}

function NovoCartao([string]$fundo = $null) {
    $b = New-Object Windows.Controls.Border
    $b.Background = Pincel ($(if ($fundo) { $fundo } else { $Cores.Cartao }))
    $b.BorderBrush = Pincel $Cores.Borda
    $b.BorderThickness = 1
    $b.CornerRadius = 10
    $b.Padding = '22,19'
    return $b
}

<#
    Cartao de metrica: numero grande, rotulo pequeno, icone.

    A hierarquia aqui e deliberada. Quem abre a janela pela manha quer ler
    UM numero e saber se pode tocar a vida. O numero e o maior elemento da
    tela; o resto e contexto.
#>
function CartaoMetrica([char]$icone, [string]$valor, [string]$rotulo, [string]$cor, [string]$rodape) {
    $c = NovoCartao
    $g = New-Object Windows.Controls.Grid
    $g.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition)) | Out-Null
    $g.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition)) | Out-Null
    $g.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition)) | Out-Null
    $g.RowDefinitions[0].Height = 'Auto'
    $g.RowDefinitions[1].Height = 'Auto'
    $g.RowDefinitions[2].Height = 'Auto'

    $topo = New-Object Windows.Controls.StackPanel
    $topo.Orientation = 'Horizontal'
    $ic = NovoIcone $icone 15 $cor
    $ic.Margin = '0,0,8,0'
    $topo.Children.Add($ic) | Out-Null
    $r = NovoTexto $rotulo 11.5 $Cores.Texto2 'SemiBold'
    $r.VerticalAlignment = 'Center'
    $topo.Children.Add($r) | Out-Null
    [Windows.Controls.Grid]::SetRow($topo, 0)
    $g.Children.Add($topo) | Out-Null

    <#
        O TAMANHO DA LETRA SAI DO TEXTO, E NAO DO GOSTO.

        Fixo em 30, "nao agendado" transbordava o cartao e invadia o vizinho -
        visto numa foto da propria tela. Numero curto quer ser grande; frase
        quer caber.
    #>
    $tamanho = if ($valor.Length -le 7) { 30 }
               elseif ($valor.Length -le 11) { 24 }
               elseif ($valor.Length -le 16) { 19 } else { 16 }
    $v = NovoTexto $valor $tamanho $Cores.Texto 'Bold'
    $v.Margin = '0,10,0,0'
    $v.LineHeight = $tamanho + 4
    [Windows.Controls.Grid]::SetRow($v, 1)
    $g.Children.Add($v) | Out-Null

    if ($rodape) {
        $f = NovoTexto $rodape 11.5 $Cores.Texto3
        $f.Margin = '0,5,0,0'
        [Windows.Controls.Grid]::SetRow($f, 2)
        $g.Children.Add($f) | Out-Null
    }

    $c.Child = $g
    return $c
}

<#
    Faixa de veredito: a primeira coisa que se le na tela.

    Um bloco largo e colorido no topo, com icone grande e uma frase. Se o
    tecnico ler so isto e fechar a janela, ele ja sabe o essencial - e isso e
    o objetivo, nao um efeito colateral.
#>
function FaixaVeredito([string]$estado, [string]$titulo, [string]$detalhe) {
    $conf = switch ($estado) {
        'ok'      { @{ Cor = $Cores.Verde;    Fundo = $Cores.VerdeFundo;    Icone = $Icones.Certo  } }
        'aviso'   { @{ Cor = $Cores.Amarelo;  Fundo = $Cores.AmareloFundo;  Icone = $Icones.Alerta } }
        'erro'    { @{ Cor = $Cores.Vermelho; Fundo = $Cores.VermelhoFundo; Icone = $Icones.Erro   } }
        default   { @{ Cor = $Cores.Azul;     Fundo = $Cores.AzulFundo;     Icone = $Icones.Info   } }
    }

    $b = New-Object Windows.Controls.Border
    $b.Background = Pincel $conf.Fundo
    $b.BorderBrush = Pincel $conf.Cor
    $b.BorderThickness = '4,0,0,0'
    $b.CornerRadius = 10
    $b.Padding = '24,20'
    $b.Margin = '0,0,0,20'

    $g = New-Object Windows.Controls.Grid
    $c0 = New-Object Windows.Controls.ColumnDefinition; $c0.Width = 'Auto'
    $c1 = New-Object Windows.Controls.ColumnDefinition; $c1.Width = '*'
    $g.ColumnDefinitions.Add($c0) | Out-Null
    $g.ColumnDefinitions.Add($c1) | Out-Null

    $ic = NovoIcone $conf.Icone 30 $conf.Cor
    $ic.Margin = '0,0,18,0'
    $ic.VerticalAlignment = 'Center'
    [Windows.Controls.Grid]::SetColumn($ic, 0)
    $g.Children.Add($ic) | Out-Null

    $sp = New-Object Windows.Controls.StackPanel
    $sp.VerticalAlignment = 'Center'
    $t = NovoTexto $titulo 18 $Cores.Texto 'SemiBold'
    $sp.Children.Add($t) | Out-Null
    if ($detalhe) {
        $d = NovoTexto $detalhe 13 $Cores.Texto2
        $d.Margin = '0,5,0,0'
        $sp.Children.Add($d) | Out-Null
    }
    [Windows.Controls.Grid]::SetColumn($sp, 1)
    $g.Children.Add($sp) | Out-Null

    $b.Child = $g
    return $b
}

<#
    Linha de item protegido.

    Uma por VM, banco ou imagem. Mostra icone do tipo, nome, o que garante a
    consistencia, quando foi a ultima vez e o tamanho.

    O texto da consistencia aparece SEMPRE, mesmo quando esta tudo certo.
    Nao e enfeite: "application-consistent" e "crash-consistent" sao a
    diferenca entre um backup com promessa e um backup com torcida, e quem
    opera precisa ver isso sem clicar em nada.
#>
function LinhaItem([string]$tipo, [string]$nome, [string]$consistencia,
                   [string]$estado, [string]$quando, [string]$tamanho) {

    $conf = switch ($estado) {
        'ok'    { @{ Cor = $Cores.Verde;    Icone = $Icones.Certo  } }
        'aviso' { @{ Cor = $Cores.Amarelo;  Icone = $Icones.Alerta } }
        'erro'  { @{ Cor = $Cores.Vermelho; Icone = $Icones.Erro   } }
        default { @{ Cor = $Cores.Texto3;   Icone = $Icones.Info   } }
    }
    $icoTipo = switch ($tipo) {
        'vm'        { $Icones.Maquina  }
        'imagem'    { $Icones.Servidor }
        'firebird'  { $Icones.Banco    }
        'sqlserver' { $Icones.Banco    }
        default     { $Icones.Disco    }
    }

    $b = New-Object Windows.Controls.Border
    $b.Background = Pincel $Cores.CartaoAlto
    $b.CornerRadius = 8
    $b.Padding = '16,13'
    $b.Margin = '0,0,0,8'

    $g = New-Object Windows.Controls.Grid
    foreach ($w in @('Auto','*','Auto','Auto')) {
        $cd = New-Object Windows.Controls.ColumnDefinition
        $cd.Width = $w
        $g.ColumnDefinitions.Add($cd) | Out-Null
    }

    $ic = NovoIcone $icoTipo 19 $Cores.Texto2
    $ic.Margin = '0,0,15,0'
    [Windows.Controls.Grid]::SetColumn($ic, 0)
    $g.Children.Add($ic) | Out-Null

    $sp = New-Object Windows.Controls.StackPanel
    $sp.VerticalAlignment = 'Center'
    $n = NovoTexto $nome 14 $Cores.Texto 'SemiBold'
    $sp.Children.Add($n) | Out-Null
    if ($consistencia) {
        $corC = if ($consistencia -match 'CRASH') { $Cores.Amarelo } else { $Cores.Texto2 }
        $c = NovoTexto $consistencia 11.5 $corC
        $c.Margin = '0,3,0,0'
        $sp.Children.Add($c) | Out-Null
    }
    [Windows.Controls.Grid]::SetColumn($sp, 1)
    $g.Children.Add($sp) | Out-Null

    $dir = New-Object Windows.Controls.StackPanel
    $dir.VerticalAlignment = 'Center'
    $dir.Margin = '16,0,16,0'
    if ($tamanho) {
        $tm = NovoTexto $tamanho 13 $Cores.Texto
        $tm.HorizontalAlignment = 'Right'
        $dir.Children.Add($tm) | Out-Null
    }
    if ($quando) {
        $q = NovoTexto $quando 11.5 $Cores.Texto3
        $q.HorizontalAlignment = 'Right'
        $q.Margin = '0,3,0,0'
        $dir.Children.Add($q) | Out-Null
    }
    [Windows.Controls.Grid]::SetColumn($dir, 2)
    $g.Children.Add($dir) | Out-Null

    $marcador = NovoIcone $conf.Icone 17 $conf.Cor
    [Windows.Controls.Grid]::SetColumn($marcador, 3)
    $g.Children.Add($marcador) | Out-Null

    $b.Child = $g
    return $b
}

<#
    Rosca de proporcao, desenhada com dois arcos.

    Serve para "quanto do que existe neste servidor esta protegido" e para
    ocupacao de disco. Um numero sozinho nao mostra proporcao; a rosca mostra
    de relance, e o numero no meio da a precisao.

    Desenhada com Path e ArcSegment porque WPF nao traz grafico pronto, e
    trazer biblioteca de terceiro para desenhar um circulo seria acrescentar
    dependencia - e mais uma coisa para quebrar num servidor de cartorio - por
    um arco.
#>
function Rosca([double]$fracao, [string]$cor, [string]$numero, [string]$rotulo, [double]$diametro = 132) {
    $g = New-Object Windows.Controls.Grid
    $g.Width = $diametro; $g.Height = $diametro

    $raio = ($diametro / 2) - 9
    $centro = $diametro / 2

    # trilho
    $trilho = New-Object Windows.Shapes.Ellipse
    $trilho.Width = $raio * 2; $trilho.Height = $raio * 2
    $trilho.Stroke = Pincel $Cores.Borda
    $trilho.StrokeThickness = 11
    $trilho.HorizontalAlignment = 'Center'
    $trilho.VerticalAlignment = 'Center'
    $g.Children.Add($trilho) | Out-Null

    if ($fracao -gt 0) {
        # Um arco de 360 graus exatos e ambiguo para o WPF (inicio e fim no
        # mesmo ponto): ele desenha NADA. Por isso o circulo cheio vira uma
        # elipse inteira, e so o resto usa arco.
        if ($fracao -ge 0.999) {
            $cheio = New-Object Windows.Shapes.Ellipse
            $cheio.Width = $raio * 2; $cheio.Height = $raio * 2
            $cheio.Stroke = Pincel $cor
            $cheio.StrokeThickness = 11
            $cheio.HorizontalAlignment = 'Center'
            $cheio.VerticalAlignment = 'Center'
            $g.Children.Add($cheio) | Out-Null
        } else {
            $angulo = $fracao * 2 * [math]::PI
            $ini = New-Object Windows.Point($centro, ($centro - $raio))
            $fim = New-Object Windows.Point(
                ($centro + $raio * [math]::Sin($angulo)),
                ($centro - $raio * [math]::Cos($angulo)))

            $arco = New-Object Windows.Media.ArcSegment
            $arco.Point = $fim
            $arco.Size = New-Object Windows.Size($raio, $raio)
            $arco.SweepDirection = 'Clockwise'
            $arco.IsLargeArc = ($fracao -gt 0.5)

            $fig = New-Object Windows.Media.PathFigure
            $fig.StartPoint = $ini
            $fig.Segments.Add($arco) | Out-Null

            $geo = New-Object Windows.Media.PathGeometry
            $geo.Figures.Add($fig) | Out-Null

            $caminho = New-Object Windows.Shapes.Path
            $caminho.Data = $geo
            $caminho.Stroke = Pincel $cor
            $caminho.StrokeThickness = 11
            $caminho.StrokeStartLineCap = 'Round'
            $caminho.StrokeEndLineCap = 'Round'
            $g.Children.Add($caminho) | Out-Null
        }
    }

    $meio = New-Object Windows.Controls.StackPanel
    $meio.HorizontalAlignment = 'Center'
    $meio.VerticalAlignment = 'Center'
    $n = NovoTexto $numero 25 $Cores.Texto 'Bold'
    $n.HorizontalAlignment = 'Center'
    $n.TextWrapping = 'NoWrap'
    $meio.Children.Add($n) | Out-Null
    if ($rotulo) {
        $r = NovoTexto $rotulo 10.5 $Cores.Texto3
        $r.HorizontalAlignment = 'Center'
        $meio.Children.Add($r) | Out-Null
    }
    $g.Children.Add($meio) | Out-Null

    return $g
}

# Barra horizontal de proporcao, para ocupacao de disco e progresso.
function Barra([double]$fracao, [string]$cor, [double]$altura = 7) {
    $g = New-Object Windows.Controls.Grid
    $g.Height = $altura

    $trilho = New-Object Windows.Controls.Border
    $trilho.Background = Pincel $Cores.Borda
    $trilho.CornerRadius = ($altura / 2)
    $g.Children.Add($trilho) | Out-Null

    $frente = New-Object Windows.Controls.Border
    $frente.Background = Pincel $cor
    $frente.CornerRadius = ($altura / 2)
    $frente.HorizontalAlignment = 'Left'
    # A largura em pixels so existe depois do layout. Um Grid interno com duas
    # colunas proporcionais resolve sem precisar saber a largura.
    $interno = New-Object Windows.Controls.Grid
    $ca = New-Object Windows.Controls.ColumnDefinition
    $cb = New-Object Windows.Controls.ColumnDefinition
    $ca.Width = New-Object Windows.GridLength($fracao, 'Star')
    $cb.Width = New-Object Windows.GridLength((1 - $fracao), 'Star')
    $interno.ColumnDefinitions.Add($ca) | Out-Null
    $interno.ColumnDefinitions.Add($cb) | Out-Null
    [Windows.Controls.Grid]::SetColumn($frente, 0)
    $interno.Children.Add($frente) | Out-Null
    $g.Children.Add($interno) | Out-Null

    return $g
}

function Secao([string]$titulo, [string]$sub) {
    $sp = New-Object Windows.Controls.StackPanel
    $sp.Margin = '0,26,0,12'
    $t = NovoTexto $titulo 15 $Cores.Texto 'SemiBold'
    $sp.Children.Add($t) | Out-Null
    if ($sub) {
        $s = NovoTexto $sub 12 $Cores.Texto3
        $s.Margin = '0,3,0,0'
        $sp.Children.Add($s) | Out-Null
    }
    return $sp
}

<#
    Campo de texto com rotulo.

    Devolve o Border para colocar na tela E a caixa de texto, para quem
    montou poder ler o valor depois. Sem devolver as duas coisas, seria
    preciso sair procurando o controle na arvore visual - que funciona e e
    horrivel de ler.
#>
function CampoTexto([string]$rotulo, [string]$valor, [string]$dica, [bool]$senha = $false) {
    $sp = New-Object Windows.Controls.StackPanel
    $sp.Margin = '0,0,0,16'

    $r = NovoTexto $rotulo 11.5 $Cores.Texto2 'SemiBold'
    $sp.Children.Add($r) | Out-Null

    $borda = New-Object Windows.Controls.Border
    $borda.Background = Pincel $Cores.Fundo
    $borda.BorderBrush = Pincel $Cores.Borda
    $borda.BorderThickness = 1
    $borda.CornerRadius = 6
    $borda.Margin = '0,7,0,0'
    $borda.Padding = '12,0'

    if ($senha) {
        $caixa = New-Object Windows.Controls.PasswordBox
        $caixa.Password = $valor
    } else {
        $caixa = New-Object Windows.Controls.TextBox
        $caixa.Text = $valor
    }
    $caixa.Background = New-Object Windows.Media.SolidColorBrush([Windows.Media.Colors]::Transparent)
    $caixa.BorderThickness = 0
    $caixa.Foreground = Pincel $Cores.Texto
    $caixa.FontSize = 13.5
    $caixa.Height = 38
    $caixa.VerticalContentAlignment = 'Center'
    $caixa.CaretBrush = Pincel $Cores.Azul
    $borda.Child = $caixa
    $sp.Children.Add($borda) | Out-Null

    if ($dica) {
        $d = NovoTexto $dica 11 $Cores.Texto3
        $d.Margin = '0,6,0,0'
        $sp.Children.Add($d) | Out-Null
    }

    return [PSCustomObject]@{ Elemento = $sp; Caixa = $caixa }
}

# Linha de "rotulo: valor" para mostrar configuracao que nao se edita aqui.
function LinhaInfo([string]$rotulo, [string]$valor, [string]$cor = $null) {
    $g = New-Object Windows.Controls.Grid
    $g.Margin = '0,0,0,11'
    $ca = New-Object Windows.Controls.ColumnDefinition; $ca.Width = '190'
    $cb = New-Object Windows.Controls.ColumnDefinition; $cb.Width = '*'
    $g.ColumnDefinitions.Add($ca) | Out-Null
    $g.ColumnDefinitions.Add($cb) | Out-Null

    $r = NovoTexto $rotulo 12.5 $Cores.Texto3
    [Windows.Controls.Grid]::SetColumn($r, 0)
    $g.Children.Add($r) | Out-Null

    $v = NovoTexto $valor 12.5 $(if ($cor) { $cor } else { $Cores.Texto })
    [Windows.Controls.Grid]::SetColumn($v, 1)
    $g.Children.Add($v) | Out-Null

    return $g
}

function NovoBotao([string]$texto, [char]$icone, [bool]$primario, $janela) {
    $b = New-Object Windows.Controls.Button
    $b.Content = $texto
    $b.Tag = [string]$icone
    $b.Style = $janela.FindResource($(if ($primario) { 'BotaoPrimario' } else { 'BotaoSecundario' }))
    return $b
}

# Bloco de aviso dentro de uma tela, para o que precisa ser lido antes de agir.
function BlocoAviso([string]$estado, [string]$texto) {
    $conf = switch ($estado) {
        'perigo' { @{ Cor = $Cores.Vermelho; Fundo = $Cores.VermelhoFundo; Icone = $Icones.Erro } }
        'aviso'  { @{ Cor = $Cores.Amarelo;  Fundo = $Cores.AmareloFundo;  Icone = $Icones.Alerta } }
        default  { @{ Cor = $Cores.Azul;     Fundo = $Cores.AzulFundo;     Icone = $Icones.Info } }
    }
    $b = New-Object Windows.Controls.Border
    $b.Background = Pincel $conf.Fundo
    $b.BorderBrush = Pincel $conf.Cor
    $b.BorderThickness = '3,0,0,0'
    $b.CornerRadius = 6
    $b.Padding = '16,13'
    $b.Margin = '0,0,0,16'

    $g = New-Object Windows.Controls.Grid
    $ca = New-Object Windows.Controls.ColumnDefinition; $ca.Width = 'Auto'
    $cb = New-Object Windows.Controls.ColumnDefinition; $cb.Width = '*'
    $g.ColumnDefinitions.Add($ca) | Out-Null
    $g.ColumnDefinitions.Add($cb) | Out-Null

    $ic = NovoIcone $conf.Icone 17 $conf.Cor
    $ic.Margin = '0,0,13,0'
    $ic.VerticalAlignment = 'Top'
    [Windows.Controls.Grid]::SetColumn($ic, 0)
    $g.Children.Add($ic) | Out-Null

    $t = NovoTexto $texto 12.5 $Cores.Texto
    $t.LineHeight = 19
    [Windows.Controls.Grid]::SetColumn($t, 1)
    $g.Children.Add($t) | Out-Null

    $b.Child = $g
    return $b
}

<#
    Linha de disco com caixa de marcar.

    O tamanho vem do proprio volume - usado = total menos livre - e por isso
    e INSTANTANEO. Varrer o disco para somar arquivo por arquivo levaria
    minutos e travaria a janela, para chegar praticamente no mesmo numero.

    Devolve o Border e a caixa, porque quem montou precisa ler o que foi
    marcado depois.
#>
function LinhaDisco($disco, [bool]$marcado, [scriptblock]$aoMudar) {
    $usado = [long]($disco.TotalBytes - $disco.LivreBytes)
    $fracao = if ($disco.TotalBytes -gt 0) { $usado / $disco.TotalBytes } else { 0 }

    $b = New-Object Windows.Controls.Border
    $b.Background = Pincel $Cores.CartaoAlto
    $b.CornerRadius = 8
    $b.Padding = '16,14'
    $b.Margin = '0,0,0,8'

    $g = New-Object Windows.Controls.Grid
    foreach ($w in @('Auto','*','150')) {
        $cd = New-Object Windows.Controls.ColumnDefinition
        $cd.Width = $w
        $g.ColumnDefinitions.Add($cd) | Out-Null
    }

    $marca = New-Object Windows.Controls.CheckBox
    $marca.IsChecked = $marcado
    $marca.VerticalAlignment = 'Center'
    $marca.Margin = '0,0,14,0'
    # Unidade de rede nao entra como origem: o Cofre e copia EXTERNA, e subir
    # de novo o que ja esta noutra nuvem e pagar duas vezes pela mesma coisa.
    $marca.IsEnabled = $disco.ServeParaTrabalho
    if ($aoMudar) {
        $marca.Add_Checked($aoMudar)
        $marca.Add_Unchecked($aoMudar)
    }
    [Windows.Controls.Grid]::SetColumn($marca, 0)
    $g.Children.Add($marca) | Out-Null

    $sp = New-Object Windows.Controls.StackPanel
    $sp.VerticalAlignment = 'Center'

    $topo = New-Object Windows.Controls.StackPanel
    $topo.Orientation = 'Horizontal'
    $ic = NovoIcone $Icones.Disco 17 $Cores.Texto2
    $ic.Margin = '0,0,10,0'
    $topo.Children.Add($ic) | Out-Null
    $n = NovoTexto "Disco $($disco.Unidade):" 14 $Cores.Texto 'SemiBold'
    $n.VerticalAlignment = 'Center'
    $topo.Children.Add($n) | Out-Null
    if (-not $disco.ServeParaTrabalho) {
        $t = NovoTexto "  ($($disco.Tipo) - nao entra no Cofre)" 12 $Cores.Texto3
        $t.VerticalAlignment = 'Center'
        $topo.Children.Add($t) | Out-Null
    }
    $sp.Children.Add($topo) | Out-Null

    $barra = Barra $fracao $(if ($fracao -gt 0.9) { $Cores.Vermelho }
                             elseif ($fracao -gt 0.75) { $Cores.Amarelo }
                             else { $Cores.Azul }) 5
    $barra.Margin = '0,9,0,6'
    $sp.Children.Add($barra) | Out-Null

    $sp.Children.Add((NovoTexto (
        "$(Tamanho $usado) usados de $(Tamanho $disco.TotalBytes)  -  $(Tamanho $disco.LivreBytes) livres") `
        11.5 $Cores.Texto3)) | Out-Null

    [Windows.Controls.Grid]::SetColumn($sp, 1)
    $g.Children.Add($sp) | Out-Null

    $dir = New-Object Windows.Controls.StackPanel
    $dir.VerticalAlignment = 'Center'
    $dir.Margin = '16,0,0,0'
    $v = NovoTexto (Tamanho $usado) 17 $Cores.Texto 'SemiBold'
    $v.HorizontalAlignment = 'Right'
    $dir.Children.Add($v) | Out-Null
    $r = NovoTexto 'para copiar' 11 $Cores.Texto3
    $r.HorizontalAlignment = 'Right'
    $dir.Children.Add($r) | Out-Null
    [Windows.Controls.Grid]::SetColumn($dir, 2)
    $g.Children.Add($dir) | Out-Null

    $b.Child = $g
    return [PSCustomObject]@{ Elemento = $b; Marca = $marca; Bytes = $usado }
}

<#
    O rodape do calculo: quanto foi escolhido e quanto tempo leva.

    Atualizado a cada marcacao. E a peca que responde a pergunta que importa
    na hora de escolher - "cabe na madrugada?" - em vez de deixar a conta
    para o dia da primeira execucao.
#>
function PainelDoCalculo([long]$bytes, [double]$mbps) {
    $c = NovoCartao
    $sp = New-Object Windows.Controls.StackPanel

    $g = New-Object Windows.Controls.Grid
    $ca = New-Object Windows.Controls.ColumnDefinition; $ca.Width = '*'
    $cb = New-Object Windows.Controls.ColumnDefinition; $cb.Width = '*'
    $g.ColumnDefinitions.Add($ca) | Out-Null
    $g.ColumnDefinitions.Add($cb) | Out-Null

    $esq = New-Object Windows.Controls.StackPanel
    $esq.Children.Add((NovoTexto 'ESCOLHIDO' 11 $Cores.Texto2 'SemiBold')) | Out-Null
    $t = NovoTexto (Tamanho $bytes) 26 $Cores.Texto 'Bold'
    $t.Margin = '0,7,0,0'
    $esq.Children.Add($t) | Out-Null
    $esq.Children.Add((NovoTexto "cerca de $(Tamanho ([long]($bytes * 0.5))) depois de comprimir" 11.5 $Cores.Texto3)) | Out-Null
    [Windows.Controls.Grid]::SetColumn($esq, 0)
    $g.Children.Add($esq) | Out-Null

    $dir = New-Object Windows.Controls.StackPanel
    $dir.Children.Add((NovoTexto 'TEMPO DE ENVIO' 11 $Cores.Texto2 'SemiBold')) | Out-Null

    if ($mbps -le 0) {
        $t2 = NovoTexto 'a medir' 26 $Cores.Texto3 'Bold'
        $t2.Margin = '0,7,0,0'
        $dir.Children.Add($t2) | Out-Null
        $dir.Children.Add((NovoTexto 'o teste de conexao mede a velocidade real' 11.5 $Cores.Texto3)) | Out-Null
    } else {
        $horas = HorasParaEnviar $bytes $mbps
        $v = CabeNaJanela $horas
        $cor = switch ($v.Estado) {
            'ok'    { $Cores.Verde }
            'aviso' { $Cores.Amarelo }
            'erro'  { $Cores.Vermelho }
            default { $Cores.Texto3 }
        }
        $rotulo = if ($horas -le 0.1) { 'minutos' } else { "$horas h" }
        $t2 = NovoTexto $rotulo 26 $cor 'Bold'
        $t2.Margin = '0,7,0,0'
        $dir.Children.Add($t2) | Out-Null
        $dir.Children.Add((NovoTexto "a $mbps Mbps - $($v.Texto)" 11.5 $Cores.Texto3)) | Out-Null
    }
    [Windows.Controls.Grid]::SetColumn($dir, 1)
    $g.Children.Add($dir) | Out-Null

    $sp.Children.Add($g) | Out-Null
    $c.Child = $sp
    return $c
}

<#
    Carrega os estilos compartilhados na janela.

    Feito por CODIGO, e nao com MergedDictionaries no XAML, porque o caminho
    relativo de um ResourceDictionary depende de como o XAML foi carregado -
    e o XamlReader.Load a partir de um XmlNodeReader nao tem URI base. O
    resultado seria um erro de "nao foi possivel localizar o recurso" que so
    aparece em tempo de execucao.

    Aqui o caminho e absoluto e conhecido: o arquivo esta ao lado deste.
#>
function AplicarEstilosCompartilhados($janela, [string]$pastaInterface) {
    try {
        $caminho = CaminhoDe $pastaInterface 'estilos.xaml'
        if (-not (Test-Path $caminho)) { return $false }
        $xml = [xml](Get-Content $caminho -Raw)
        $dic = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xml))
        $janela.Resources.MergedDictionaries.Add($dic)
        return $true
    } catch {
        # Estilo e acabamento: se falhar, a janela abre com o visual padrao do
        # Windows. Feio, mas funcionando - e melhor que nao abrir.
        return $false
    }
}

<#
    Mostra o caminho de destino de um item.

    Existe porque escolher uma pasta e nao saber onde ela vai parar e o tipo
    de coisa que so se descobre errada depois - no dia da restauracao, com
    alguem procurando num bucket que tem outra estrutura na cabeca.

    O texto e o caminho REAL, montado pelas mesmas funcoes que o motor usa
    na hora de enviar. Nao e um exemplo aproximado: e o que vai acontecer.
#>
function LinhaDestino([string]$caminho) {
    $b = New-Object Windows.Controls.Border
    $b.Background = Pincel $Cores.Fundo
    $b.BorderBrush = Pincel $Cores.Borda
    $b.BorderThickness = 1
    $b.CornerRadius = 5
    $b.Padding = '11,7'
    $b.Margin = '0,7,0,0'

    $g = New-Object Windows.Controls.Grid
    $ca = New-Object Windows.Controls.ColumnDefinition; $ca.Width = 'Auto'
    $cb = New-Object Windows.Controls.ColumnDefinition; $cb.Width = '*'
    $g.ColumnDefinitions.Add($ca) | Out-Null
    $g.ColumnDefinitions.Add($cb) | Out-Null

    $ic = NovoIcone $Icones.Nuvem 13 $Cores.Texto3
    $ic.Margin = '0,0,9,0'
    [Windows.Controls.Grid]::SetColumn($ic, 0)
    $g.Children.Add($ic) | Out-Null

    $t = NovoTexto $caminho 11.5 $Cores.Texto2
    # Fonte de largura fixa: caminho e para ser lido caractere a caractere,
    # e barra com barra invertida se confundem em fonte proporcional.
    $t.FontFamily = New-Object Windows.Media.FontFamily('Consolas, Courier New')
    $t.TextWrapping = 'Wrap'
    [Windows.Controls.Grid]::SetColumn($t, 1)
    $g.Children.Add($t) | Out-Null

    $b.Child = $g
    return $b
}

<#
    A linha do tempo das ultimas execucoes.

    Um painel de backup sem historico visivel obriga a pessoa a abrir outra
    tela para responder a pergunta mais comum: "isso vem rodando?". Uma coluna
    por execucao, verde quando deu tudo certo, vermelha quando alguem falhou,
    responde isso de relance.

    A altura da coluna e o VOLUME enviado, nao o tempo. Volume que despenca de
    um dia para o outro e o sinal de que alguma coisa parou de ser copiada -
    e esse e o defeito que ninguem percebe, porque a execucao continua
    "terminando com sucesso".
#>
function LinhaDoTempo($execucoes, [double]$altura = 96) {
    $g = New-Object Windows.Controls.Grid
    $g.Height = $altura
    if (@($execucoes).Count -eq 0) { return $g }

    $sp = New-Object Windows.Controls.StackPanel
    $sp.Orientation = 'Horizontal'
    $sp.VerticalAlignment = 'Bottom'
    $sp.HorizontalAlignment = 'Left'

    $maior = 1
    foreach ($e in $execucoes) { if ([long]$e.Bytes -gt $maior) { $maior = [long]$e.Bytes } }

    foreach ($e in $execucoes) {
        $col = New-Object Windows.Controls.StackPanel
        $col.Margin = '0,0,6,0'
        $col.VerticalAlignment = 'Bottom'

        $fracao = [double]([long]$e.Bytes) / $maior
        # Piso de 6 px: uma execucao que enviou quase nada ainda precisa
        # aparecer, senao some justamente o caso que interessa olhar.
        $h = [math]::Max(6, [math]::Round(($altura - 22) * $fracao))

        $b = New-Object Windows.Controls.Border
        $b.Width = 16
        $b.Height = $h
        $b.CornerRadius = '4,4,0,0'
        $b.Background = Pincel $(if ($e.Falhou) { $Cores.Vermelho } else { $Cores.Verde })
        $b.ToolTip = "$($e.Rotulo) - $($e.Texto)"
        $col.Children.Add($b) | Out-Null

        $d = NovoTexto $e.Dia 9.5 $Cores.Texto3
        $d.HorizontalAlignment = 'Center'
        $d.Margin = '0,5,0,0'
        $col.Children.Add($d) | Out-Null

        $sp.Children.Add($col) | Out-Null
    }
    $g.Children.Add($sp) | Out-Null
    return $g
}
