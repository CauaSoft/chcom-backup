<#
================================================================================
  CH.Com Cofre - interface

  Esta janela NAO faz backup. Ela mostra o que o motor esta fazendo e manda
  ele fazer coisas.

  O porque esta em docs\POR-QUE-MOTOR-SEPARADO-DA-INTERFACE.md, e resume-se a
  uma frase: backup de cartorio roda as 2 da manha sem ninguem na frente, e um
  backup que morre quando alguem fecha a janela nao e backup.

  A janela le estado.json e dispara o motor como processo separado.
================================================================================
#>

[CmdletBinding()]
param(
    # Monta tudo mas nao abre a janela. Serve para conferir, sem interface,
    # que todas as telas montam - inclusive as que so aparecem depois de
    # alguem clicar no menu. Abrir a janela so prova a PRIMEIRA tela.
    [switch]$NaoAbrir
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$aqui = Split-Path -Parent $MyInvocation.MyCommand.Path
$raiz = Split-Path -Parent $aqui

. (Join-Path $raiz 'modulos\comum.ps1')
. (Join-Path $raiz 'modulos\descobrir.ps1')
. (Join-Path $raiz 'modulos\planejar.ps1')
. (Join-Path $raiz 'modulos\conferir-nuvem.ps1')
. (Join-Path $raiz 'modulos\configurar.ps1')
. (Join-Path $raiz 'modulos\enviar.ps1')
. (Join-Path $raiz 'modulos\gerente.ps1')
. (Join-Path $aqui 'componentes.ps1')
. (Join-Path $aqui 'telas.ps1')

# Configuracao, estado e historico ficam em ProgramData, e nao ao lado do
# codigo: Program Files e somente leitura para quem nao e administrador.
$dados = PastaDeDados $raiz

# ------------------------------------------------------------------------------
#  Janela
# ------------------------------------------------------------------------------
$xml = [xml](Get-Content (CaminhoDe $aqui 'janela.xaml') -Raw)
$leitor = New-Object System.Xml.XmlNodeReader $xml
$janela = [Windows.Markup.XamlReader]::Load($leitor)

# A barra de rolagem e os demais estilos comuns vem de estilos.xaml, um
# arquivo so: estilo duplicado nos dois XAML sai de sincronia, e foi assim
# que os botoes do assistente ficaram com nome diferente dos da janela.
[void](AplicarEstilosCompartilhados $janela $aqui)

$pastaMarca = CaminhoDe $raiz 'marca'
try {
    $img = New-Object Windows.Media.Imaging.BitmapImage
    $img.BeginInit()
    $img.UriSource = New-Object Uri((CaminhoDe $pastaMarca 'logo-256.png'))
    # Sem OnLoad o arquivo fica travado pelo processo e o instalador nao
    # consegue atualizar a marca com a janela aberta.
    $img.CacheOption = 'OnLoad'
    $img.EndInit()
    $janela.FindName('imgLogo').Source = $img
} catch { }
<#
    O MAIOR QUADRO DO .ico, e nao o primeiro.

    Um .ico guarda varias imagens - 16, 32, 48, 256 - e o BitmapImage pega
    SEMPRE a menor, seja qual for a ordem no arquivo. Medido: "a janela
    carrega: 16x16". A janela abria com um icone de 16 pixels esticado, e na
    barra de tarefas isso aparece como um borrao.

    Reordenar o arquivo nao resolve - foi tentado. O jeito e ler os quadros e
    escolher.

    OnLoad continua necessario: sem ele o WPF mantem o arquivo ABERTO enquanto
    a janela existir, e o chcom.ico fica travado. Pego ao tentar remontar o
    pacote com o programa aberto - o que impediria o instalador de atualizar a
    marca sem fechar tudo antes.
#>
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

$ico = IconeGrande (CaminhoDe $pastaMarca 'chcom.ico')
if ($ico) { $janela.Icon = $ico }

# ------------------------------------------------------------------------------
#  Dados
#
#  O inventario roda uma vez na abertura: descobrir VM e banco leva alguns
#  segundos, e refazer a cada troca de tela deixaria a janela lenta a toa.
<#
    O ESTADO COMPARTILHADO E UM HASHTABLE, NAO VARIAVEIS SOLTAS.

    Isto nao e estilo: e a correcao de um defeito que fez o menu inteiro nao
    funcionar.

    Os manipuladores de clique sao criados com GetNewClosure(), que congela o
    valor da variavel do laco - sem isso, todos os itens abririam a ultima
    tela. So que GetNewClosure() da ao scriptblock um escopo de script
    PROPRIO. Dentro dele, "$script:Tela = x" escreve numa variavel de outro
    escopo, e o script principal nunca ve a mudanca.

    O sintoma: clicar no menu chamava a funcao de desenhar, mas sempre com a
    mesma tela. Parecia que o botao nao respondia.

    Hashtable e tipo de REFERENCIA. O closure captura o mesmo objeto, e mudar
    uma chave e visivel de todo lugar. Conferido disparando os quatro itens
    do menu: protegido > executar > historico > painel.
#>
$Ctx = @{
    Ambiente       = $null
    Plano          = $null
    Tela           = 'painel'
    EstavaRodando  = $false
    # A leitura do parque, guardada entre telas: cada uma e uma ida a AWS.
    Parque         = $null
}

function RecarregarInventario {
    $Ctx.Ambiente = DescobrirAmbiente
    # A config traz as pastas escolhidas a mao, que a deteccao nao alcanca.
    $Ctx.Plano = MontarPlano $Ctx.Ambiente (LerConfiguracao (CaminhoDe $dados 'cofre.conf'))
}

function LerEstado {
    $arq = CaminhoDe $dados 'estado.json'
    if (-not (Test-Path $arq)) { return $null }
    try { return (Get-Content $arq -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

<#
    Dispara o motor.

    Processo separado, janela escondida. A interface nao espera nem acompanha
    diretamente: ela le estado.json, que o motor atualiza a cada passo. Fechar
    a janela agora nao interrompe nada.
#>
<#
    Dispara o motor, ELEVADO.

    O -Verb RunAs nao e capricho. O que o motor faz exige administrador:

        Export-VM              exportar maquina virtual
        wbadmin                imagem do servidor
        gravar em ProgramData  configuracao, estado e historico

    Sem elevar, o botao "Executar agora" abriria um processo que falharia em
    silencio - e a janela ficaria esperando um estado.json que nunca seria
    escrito. Pior que nao funcionar: parecer que esta funcionando.

    Quando o Agendador roda sozinho isso nao se aplica: as tarefas ja sao
    registradas como SYSTEM.
#>
function DispararMotor([string]$modo) {
    $argumentos = @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden',
                    '-File', ('"' + (CaminhoDe $raiz 'cofre.ps1') + '"'))
    if ($modo -eq 'tudo')   { $argumentos += '-Tudo' }
    if ($modo -eq 'bancos') { $argumentos += '-SomenteBancos' }
    try {
        Start-Process powershell -ArgumentList $argumentos -Verb RunAs -WindowStyle Hidden
    } catch {
        # O usuario recusou o aviso do Windows. Nao e erro: e uma decisao.
        [Windows.MessageBox]::Show(
            'O Windows precisa de permissao de administrador para fazer a copia. Nada foi feito.',
            'CH.Com Cofre', 'OK', 'Warning') | Out-Null
    }
}

# ------------------------------------------------------------------------------
#  Navegacao
# ------------------------------------------------------------------------------
$area = $janela.FindName('areaConteudo')
$titulo = $janela.FindName('txtTituloTela')
$subtitulo = $janela.FindName('txtSubtitulo')
$Ctx.Tela = 'painel'

function Desenhar {
    $estado = LerEstado
    $area.Children.Clear()

    switch ($Ctx.Tela) {
        'parque' {
            $titulo.Text = 'Todos os cartorios'
            $subtitulo.Text = 'Lido direto do Cofre na AWS, sem servidor no meio'
            $temConf = Test-Path (CaminhoDe $dados 'rclone.conf')
            $cfg = LerConfiguracao (CaminhoDe $dados 'cofre.conf')

            <#
                A leitura do bucket e GUARDADA entre trocas de tela.

                Cada leitura e uma ida a AWS: refazer a cada clique no menu
                deixaria a janela lenta e gastaria requisicao a toa. O botao
                "Atualizar do bucket" e quem forca uma leitura nova.
            #>
            if ($temConf -and -not $Ctx.Parque) {
                $rcl = CaminhoDoRclone $raiz
                if ($rcl) {
                    $Ctx.Parque = LerParque -Rclone $rcl `
                        -Config (CaminhoDe $dados 'rclone.conf') `
                        -Bucket $(if ($cfg -and $cfg.Bucket) { $cfg.Bucket } else { "backup-aws-ch" })
                }
            }
            $area.Children.Add((TelaParque $Ctx.Parque $temConf $janela {
                $Ctx.Parque = $null
                Desenhar
            } { AbrirAssistente })) | Out-Null
        }
        'painel' {
            $titulo.Text = 'Painel'
            $subtitulo.Text = "$($Ctx.Ambiente.Maquina)  -  $($Ctx.Ambiente.Windows)"
            $temConfig = Test-Path (CaminhoDe $dados 'cofre.conf')
            $area.Children.Add((TelaPainel $Ctx.Ambiente $Ctx.Plano $estado `
                $temConfig $janela { AbrirAssistente })) | Out-Null
        }
        'protegido' {
            $titulo.Text = 'O que e protegido'
            $subtitulo.Text = 'Detectado automaticamente neste servidor'
            $area.Children.Add((TelaProtegido $Ctx.Ambiente $Ctx.Plano $estado `
                $Ctx.Nuvem $janela {
                    <#
                        A leitura fica GUARDADA entre trocas de tela: cada
                        conferencia e uma ida a AWS, e refazer a cada clique no
                        menu gastaria requisicao a toa. O botao "Conferir de
                        novo" e quem forca.
                    #>
                    $janela.Cursor = [Windows.Input.Cursors]::Wait
                    $janela.Dispatcher.Invoke([action]{}, [Windows.Threading.DispatcherPriority]::Render)
                    try {
                        $cfg = LerConfiguracao (CaminhoDe $dados 'cofre.conf')
                        $rcl = CaminhoDoRclone $raiz
                        $arq = CaminhoDe $dados 'rclone.conf'
                        if (-not $cfg -or -not $rcl -or -not (Test-Path $arq)) {
                            $Ctx.Nuvem = [PSCustomObject]@{ Itens=@(); Erro='este servidor ainda nao tem destino configurado.'; TotalBytes=0; Lidos=0 }
                        } else {
                            $Ctx.Nuvem = ConferirNaNuvem -Rclone $rcl -Config $arq `
                                -Cartorio (NomeParaDestino $cfg.Cartorio) -Plano $Ctx.Plano `
                                -Servidor (NomeParaDestino $Ctx.Ambiente.Maquina) `
                                -Remoto $(if ($cfg.Remoto) { $cfg.Remoto } else { 'cofre' })
                        }
                    } finally { $janela.Cursor = $null }
                    Desenhar
                })) | Out-Null
        }
        'executar' {
            $titulo.Text = 'Executar agora'
            $subtitulo.Text = 'Copia consistente, conferida, cifrada e enviada'
            $area.Children.Add((TelaExecutar $Ctx.Ambiente $Ctx.Plano $estado {
                param($modo)
                DispararMotor $modo
                Start-Sleep -Milliseconds 900
                Desenhar
            })) | Out-Null
        }
        'historico' {
            $titulo.Text = 'Historico'
            $subtitulo.Text = 'Todas as execucoes registradas'
            $area.Children.Add((TelaHistorico $raiz)) | Out-Null
        }
        'restaurar' {
            $titulo.Text = 'Restaurar'
            $subtitulo.Text = 'Recuperar do Cofre na AWS'
            $cfg = LerConfiguracao (CaminhoDe $dados 'cofre.conf')
            $pontos = $null; $erro = $null
            if ($cfg) {
                $lidos = LerPontosDeRecuperacao $raiz $cfg
                $pontos = $lidos.Pontos
                $erro = $lidos.Erro
            }
            $area.Children.Add((TelaRestaurar $cfg $pontos $erro $janela {
                param($acao, $caminho)
                AcaoDeRestauracao $acao $caminho
            })) | Out-Null
        }
        'destino' {
            $titulo.Text = 'Destino na nuvem'
            $subtitulo.Text = 'Para onde as copias vao'
            $cfg = LerConfiguracao (CaminhoDe $dados 'cofre.conf')
            $temRclone = [bool](CaminhoDoRclone $raiz)
            $area.Children.Add((TelaDestino $cfg $temRclone $janela {
                TestarDestino
            })) | Out-Null
        }
        'chave' {
            $titulo.Text = 'Chave'
            $subtitulo.Text = 'O ativo mais importante do sistema'
            $cfg = LerConfiguracao (CaminhoDe $dados 'cofre.conf')
            $temConf = Test-Path (CaminhoDe $dados 'rclone.conf')
            $area.Children.Add((TelaChave $cfg $temConf $janela)) | Out-Null
        }
        'config' {
            $titulo.Text = 'Configuracao'
            $subtitulo.Text = 'Agendamento e ajustes deste servidor'
            $cfg = LerConfiguracao (CaminhoDe $dados 'cofre.conf')
            $tarefas = LerTarefasAgendadas
            $area.Children.Add((TelaConfiguracao $cfg $tarefas $janela {
                param($caminhoBanco)
                SalvarBancoFirebird $caminhoBanco
            })) | Out-Null
        }
        default {
            $titulo.Text = 'Em construcao'
            $subtitulo.Text = ''
            $area.Children.Add((FaixaVeredito 'info' 'Esta tela ainda esta sendo construida' '')) | Out-Null
        }
    }

    AtualizarEstadoDoTopo $estado
}

<#
    As acoes que a janela dispara.

    Todas abrem um console visivel de proposito, em vez de rodar escondido.
    Descongelar e baixar do Deep Archive sao operacoes longas, com mensagens
    que importam - e uma janela que "some e volta depois" nao diz a ninguem
    se esta funcionando. O console mostra o que esta acontecendo e fica
    aberto no fim, para dar tempo de ler.
#>
<#
    Abre o assistente de configuracao.

    ELEVADO, porque ele grava o rclone.conf em ProgramData, ajusta as
    permissoes desse arquivo e registra as tarefas no Agendador.

    NAO E MAIS -Wait. A versao anterior travou a janela num teste real, e o
    motivo e simples: -Wait bloqueia a thread da interface, entao o programa
    INTEIRO congela enquanto o assistente estiver aberto. Se o assistente
    ainda por cima nao aparecer, a janela morre de pe, sem mensagem nenhuma.

    Agora o processo sobe solto e quem espera e o relogio de 2 segundos, que
    ja existe. A janela continua respondendo, e quando o assistente fecha ela
    le a configuracao de novo sozinha.
#>
function AbrirAssistente {
    # Um segundo assistente gravaria o mesmo arquivo de configuracao ao mesmo
    # tempo que o primeiro.
    if ($Ctx.Assistente -and -not $Ctx.Assistente.HasExited) {
        [Windows.MessageBox]::Show(
            'O assistente de configuracao ja esta aberto. Procure a janela dele na barra de tarefas.',
            'CH.Com Cofre', 'OK', 'Information') | Out-Null
        return
    }
    try {
        $Ctx.Assistente = Start-Process powershell -Verb RunAs -PassThru -WindowStyle Hidden -ArgumentList @(
            '-NoProfile','-ExecutionPolicy','Bypass',
            '-File', (Aspas (CaminhoDe $aqui 'assistente.ps1')))
    } catch {
        $Ctx.Assistente = $null
        [Windows.MessageBox]::Show(
            'O Windows precisa de permissao de administrador para configurar o Cofre. Nada foi alterado.',
            'CH.Com Cofre', 'OK', 'Warning') | Out-Null
    }
}

function AcaoDeRestauracao([string]$acao, [string]$caminho) {
    $script = CaminhoDe $raiz 'restaurar-cofre.ps1'
    $argumentos = @('-NoExit','-NoProfile','-ExecutionPolicy','Bypass','-File', (Aspas $script))

    switch ($acao) {
        'descongelar' { $argumentos += @('-Descongelar', $caminho) }
        'situacao'    { $argumentos += @('-Situacao', $caminho) }
        'baixar' {
            # Para onde baixar e escolha de quem esta restaurando: o destino
            # muda conforme o desastre. Perguntar aqui evita despejar dezenas
            # de GB num disco que nao aguenta.
            Add-Type -AssemblyName System.Windows.Forms
            $dlg = New-Object Windows.Forms.FolderBrowserDialog
            $dlg.Description = 'Escolha a pasta onde os arquivos recuperados serao gravados'
            $dlg.ShowNewFolderButton = $true
            if ($dlg.ShowDialog() -ne 'OK') { return }
            $argumentos += @('-Baixar', $caminho, '-Para', $dlg.SelectedPath)
        }
    }
    # Le o rclone.conf, que tem acesso restrito a administradores.
    try { Start-Process powershell -ArgumentList $argumentos -Verb RunAs }
    catch { }
}

function TestarDestino {
    $cfg = LerConfiguracao (CaminhoDe $dados 'cofre.conf')
    if (-not $cfg) { return }
    $rclone = CaminhoDoRclone $raiz
    if (-not $rclone) { return }

    # Roda pelo instalador em modo de teste? Nao: o instalador gera chave.
    # Aqui o teste e so listar o bucket, que prova credencial, rede e
    # permissao sem escrever nada e sem custo.
    $comando = "& '$rclone' lsd '$($cfg.Remoto):' --config '$(CaminhoDe $dados 'rclone.conf')'; " +
               "Write-Host ''; Write-Host '  Se apareceu a lista acima, a conexao com a AWS esta funcionando.' -ForegroundColor Green"
    # Le o rclone.conf, que so administradores enxergam.
    try { Start-Process powershell -Verb RunAs -ArgumentList @('-NoExit','-NoProfile','-Command', $comando) }
    catch { }
}

function SalvarBancoFirebird([string]$caminho) {
    $arq = CaminhoDe $dados 'cofre.conf'
    $cfg = LerConfiguracao $arq
    if (-not $cfg) { return }
    $cfg.BancoFirebird = $caminho
    GravarConfiguracao $arq $cfg
    RecarregarInventario
    Desenhar
}

function AtualizarEstadoDoTopo($estado) {
    $luz = $janela.FindName('luzEstado')
    $txt = $janela.FindName('txtEstadoTopo')
    $pilula = $janela.FindName('pilulaEstado')

    if ($estado -and $estado.Rodando) {
        $luz.Fill = Pincel $Cores.Azul
        $pilula.Background = Pincel $Cores.AzulFundo
        $txt.Text = 'copiando agora'
    } elseif ($Ctx.Plano.NaoProtegido.Count -gt 0 -or $Ctx.Plano.Tarefas.Count -eq 0) {
        $luz.Fill = Pincel $Cores.Vermelho
        $pilula.Background = Pincel $Cores.VermelhoFundo
        $txt.Text = 'nao protegido'
    } elseif ($Ctx.Plano.Avisos.Count -gt 0 -or -not $estado) {
        $luz.Fill = Pincel $Cores.Amarelo
        $pilula.Background = Pincel $Cores.AmareloFundo
        $txt.Text = if ($estado) { 'com ressalvas' } else { 'nunca copiado' }
    } else {
        $luz.Fill = Pincel $Cores.Verde
        $pilula.Background = Pincel $Cores.VerdeFundo
        $txt.Text = 'protegido'
    }
}

# ------------------------------------------------------------------------------
#  Ligacoes
# ------------------------------------------------------------------------------
$mapa = @{
    mnuParque    = 'parque'
    mnuPainel    = 'painel'
    mnuProtegido = 'protegido'
    mnuExecutar  = 'executar'
    mnuRestaurar = 'restaurar'
    mnuHistorico = 'historico'
    mnuDestino   = 'destino'
    mnuChave     = 'chave'
    mnuConfig    = 'config'
}

<#
    No cartorio, a tela "Todos os cartorios" nao existe.

    O rotulo "PROTECAO" acima dela continua, porque a secao tem mais itens.
    E $Ctx.Tela comeca em 'painel' de qualquer forma, entao nao ha caminho
    para cair numa tela escondida.

    A tranca de verdade continua sendo o IAM: a credencial do cartorio so
    alcanca o prefixo dele. Isto aqui e para nao confundir quem esta no
    balcao.
#>
$Ctx.Modo = ModoDoPrograma $raiz
if ($Ctx.Modo -ne 'gerente') {
    $itemParque = $janela.FindName('mnuParque')
    if ($itemParque) { $itemParque.Visibility = 'Collapsed' }
}
foreach ($nome in $mapa.Keys) {
    $botao = $janela.FindName($nome)
    $destino = $mapa[$nome]
    # GetNewClosure congela o valor de $destino no momento da criacao. Sem
    # isso, todos os manipuladores compartilhariam a ultima variavel do laco e
    # o menu inteiro abriria a mesma tela.
    $botao.Add_Checked({ $Ctx.Tela = $destino; Desenhar }.GetNewClosure())
}

$janela.FindName('btnAtualizar').Add_Click({
    RecarregarInventario
    Desenhar
})

<#
    Atualizacao enquanto o motor trabalha.

    Um relogio de 2 segundos releria o estado o tempo todo, inclusive parado -
    desperdicio e piscada de tela a toa. Entao ele so redesenha quando ha
    trabalho em andamento, ou quando o trabalho acabou de terminar.
#>
$Ctx.EstavaRodando = $false
$relogio = New-Object Windows.Threading.DispatcherTimer
$relogio.Interval = [TimeSpan]::FromSeconds(2)
$relogio.Add_Tick({
    # O assistente roda num processo elevado, solto. Quando ele fecha, a
    # configuracao pode ter mudado - entao a janela relanca o inventario e se
    # redesenha. Isso substitui o -Wait que travava a interface.
    if ($Ctx.Assistente -and $Ctx.Assistente.HasExited) {
        $Ctx.Assistente = $null
        RecarregarInventario
        Desenhar
    }
    $e = LerEstado
    $agora = ($e -and $e.Rodando)
    if ($agora -or $Ctx.EstavaRodando) { Desenhar }
    $Ctx.EstavaRodando = $agora
})

$janela.Add_ContentRendered({ $relogio.Start() })
$janela.Add_Closed({ $relogio.Stop() })

<#
    SEM CONFIGURACAO, O PROGRAMA SE CONFIGURA SOZINHO.

    A primeira versao chamava o assistente ANTES de a janela abrir, com -Wait.
    Duas coisas erradas: a janela ficava travada esperando o aviso do Windows,
    e quem recusasse a elevacao ficava sem nada na tela.

    A correcao de entao foi tirar tudo e deixar so um botao - o que empurrou o
    trabalho para um .bat que ninguem deveria precisar rodar.

    Agora o meio-termo, que e o que sempre deveria ter sido:

      A JANELA ABRE PRIMEIRO. Depois de desenhada - e so depois - o assistente
      sobe sozinho, num processo separado, sem travar nada. Quem recusar a
      elevacao continua com o programa na tela e o botao "Configurar agora"
      onde sempre esteve.

    UMA VEZ SO POR SESSAO. Sem essa trava, fechar o assistente sem concluir
    faria a janela reabri-lo na hora - um lacinho infinito de UAC, que e
    exatamente o tipo de coisa que faz alguem desistir do produto.
#>
$Ctx.OfereceuAssistente = $false

$janela.Add_ContentRendered({
    if ($Ctx.OfereceuAssistente) { return }
    $Ctx.OfereceuAssistente = $true
    <#
        Configurado pela metade tambem conta como nao configurado.

        cofre.conf sem rclone.conf e um estado real e silencioso: o cartorio
        aparece "configurado" na tela, o agendamento roda toda madrugada, e
        nada sai do servidor porque nao ha chave nem credencial. Acontece
        quando alguem cancela o assistente depois do passo do destino, ou
        quando o teste falha - o rclone.conf e apagado de proposito nesse
        caso, para o agendador nao ficar tentando um destino que nao funciona.

        Entao a pergunta nao e "existe cofre.conf?", e sim "da para enviar
        alguma coisa daqui?".
    #>
    $temConf  = Test-Path (CaminhoDe $dados 'cofre.conf')
    $temChave = Test-Path (CaminhoDe $dados 'rclone.conf')
    if ($temConf -and $temChave) { return }

    # Um respiro para a janela terminar de aparecer antes do aviso do Windows:
    # o pedido de elevacao em cima de uma tela ainda em branco parece travamento.
    <#
        O cronometro vai no $Ctx, e nao numa variavel local.

        O bloco do Tick roda depois, fora daqui, e resolve nomes no escopo do
        SCRIPT - nao no escopo desta funcao. Um $adiar declarado localmente
        seria $null la dentro, e $adiar.Stop() estouraria dentro de um
        manipulador de evento: janela morta, sem mensagem.

        E o mesmo tropeco que ja derrubou o menu inteiro uma vez.
    #>
    $Ctx.Adiar = New-Object Windows.Threading.DispatcherTimer
    $Ctx.Adiar.Interval = [TimeSpan]::FromMilliseconds(700)
    $Ctx.Adiar.Add_Tick({
        $Ctx.Adiar.Stop()
        AbrirAssistente
    })
    $Ctx.Adiar.Start()
})

RecarregarInventario

$janela.FindName('txtMaquina').Text = $Ctx.Ambiente.Maquina
$janela.FindName('txtVersao').Text = 'versao 1.0  -  CH.Com'

Desenhar
if (-not $NaoAbrir) { $janela.ShowDialog() | Out-Null }
