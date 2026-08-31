<#
================================================================================
  CH.Com Cofre - as telas
================================================================================
#>

function GradeDeCartoes($cartoes, [int]$colunas = 4) {
    $g = New-Object Windows.Controls.Grid
    for ($i = 0; $i -lt $colunas; $i++) {
        $cd = New-Object Windows.Controls.ColumnDefinition
        $cd.Width = New-Object Windows.GridLength(1, 'Star')
        $g.ColumnDefinitions.Add($cd) | Out-Null
    }
    $i = 0
    foreach ($c in $cartoes) {
        $c.Margin = $(if ($i -eq 0) { '0,0,7,0' }
                      elseif ($i -eq $colunas - 1) { '7,0,0,0' }
                      else { '7,0,7,0' })
        [Windows.Controls.Grid]::SetColumn($c, $i)
        $g.Children.Add($c) | Out-Null
        $i++
    }
    return $g
}

# ------------------------------------------------------------------------------
#  PAINEL
# ------------------------------------------------------------------------------
<#
    Bloco de "ainda nao configurado", com o botao de resolver.

    Aparece no lugar do veredito quando nao ha cofre.conf. A janela abre
    normalmente nesse caso, em vez de disparar o assistente sozinha e travar
    esperando o aviso do Windows - defeito real, pego em teste.
#>
function BlocoConfigurar($janela, $aoConfigurar) {
    $b = New-Object Windows.Controls.Border
    $b.Background = Pincel $Cores.VermelhoFundo
    $b.BorderBrush = Pincel $Cores.Vermelho
    $b.BorderThickness = '4,0,0,0'
    $b.CornerRadius = 10
    $b.Padding = '24,22'
    $b.Margin = '0,0,0,20'

    $g = New-Object Windows.Controls.Grid
    $ca = New-Object Windows.Controls.ColumnDefinition; $ca.Width = 'Auto'
    $cb = New-Object Windows.Controls.ColumnDefinition; $cb.Width = '*'
    $cc = New-Object Windows.Controls.ColumnDefinition; $cc.Width = 'Auto'
    $g.ColumnDefinitions.Add($ca) | Out-Null
    $g.ColumnDefinitions.Add($cb) | Out-Null
    $g.ColumnDefinitions.Add($cc) | Out-Null

    $ic = NovoIcone $Icones.Alerta 30 $Cores.Vermelho
    $ic.Margin = '0,0,18,0'
    [Windows.Controls.Grid]::SetColumn($ic, 0)
    $g.Children.Add($ic) | Out-Null

    $sp = New-Object Windows.Controls.StackPanel
    $sp.VerticalAlignment = 'Center'
    $sp.Children.Add((NovoTexto 'Este servidor ainda nao esta protegido' 18 $Cores.Texto 'SemiBold')) | Out-Null
    $d = NovoTexto ('Falta configurar o destino na AWS e gerar a chave de criptografia. ' +
                    'Leva uns cinco minutos.') 13 $Cores.Texto2
    $d.Margin = '0,5,0,0'
    $sp.Children.Add($d) | Out-Null
    [Windows.Controls.Grid]::SetColumn($sp, 1)
    $g.Children.Add($sp) | Out-Null

    $bt = NovoBotao 'Configurar agora' $Icones.Play $true $janela
    $bt.VerticalAlignment = 'Center'
    $bt.Margin = '18,0,0,0'
    $bt.Add_Click({ & $aoConfigurar }.GetNewClosure())
    [Windows.Controls.Grid]::SetColumn($bt, 2)
    $g.Children.Add($bt) | Out-Null

    $b.Child = $g
    return $b
}

<#
    Le as ultimas execucoes para a linha do tempo.

    Sai do historico gravado a cada rodada, e nao do estado atual: o estado
    conta a ultima, o historico conta a tendencia. Volume que cai pela metade
    de um dia para o outro e um defeito que nao se anuncia.
#>
function UltimasExecucoes([string]$pastaDados, [int]$quantas = 14) {
    $lista = @()
    $pasta = CaminhoDe $pastaDados 'historico'
    if (-not (Test-Path $pasta)) { return $lista }

    $arquivos = @(Get-ChildItem $pasta -Filter '*.json' -File -ErrorAction SilentlyContinue |
                  Sort-Object Name -Descending | Select-Object -First $quantas)
    # Ordem cronologica na tela: o mais antigo a esquerda, como qualquer
    # grafico de tempo. A leitura acima e do mais novo para pegar os N ultimos.
    [array]::Reverse($arquivos)

    foreach ($f in $arquivos) {
        $e = $null
        try { $e = (Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { continue }
        if (-not $e) { continue }
        $bytes = 0
        foreach ($d in @($e.Detalhes)) { if ($d.Sucesso) { $bytes += [long]$d.Bytes } }
        $q = DataOuNada $e.Terminou
        $lista += [PSCustomObject]@{
            Bytes  = $bytes
            Falhou = ([int]$e.Falhas -gt 0)
            Dia    = $(if ($q) { $q.ToString('dd/MM') } else { '?' })
            Rotulo = $(if ($q) { $q.ToString('dd/MM/yyyy HH:mm') } else { 'sem data' })
            Texto  = "$($e.Sucessos) enviado(s), $($e.Falhas) falha(s), $(Tamanho $bytes)"
        }
    }
    return $lista
}

<#
    Quando o Agendador vai rodar de novo.

    Um painel que nao responde isso obriga a abrir o Agendador de Tarefas do
    Windows para saber se o backup de hoje a noite vai acontecer.
#>
function ProximaExecucao {
    $proxima = $null
    foreach ($t in @(LerTarefasAgendadas)) {
        if ($t.Quando -match '(\d{2}/\d{2}/\d{4} \d{2}:\d{2})') {
            $d = DataOuNada $Matches[1]
            if ($d -and (-not $proxima -or $d -lt $proxima)) { $proxima = $d }
        }
    }
    return $proxima
}

function TelaPainel($ambiente, $plano, $estado, $temConfig, $janela, $aoConfigurar) {
    $sp = New-Object Windows.Controls.StackPanel

    if (-not $temConfig) {
        $sp.Children.Add((BlocoConfigurar $janela $aoConfigurar)) | Out-Null
    }

    <#
        O PLANO E O ESTADO PODEM DISCORDAR - E ISSO E A NOTICIA.

        Visto numa foto da propria tela: os cartoes diziam "ultima copia ha 9h"
        e "88,85 GB enviados", e ao lado a rosca dizia "0% protegido, 0 de 5
        itens". As duas coisas eram verdade e juntas nao queriam dizer nada.

        Acontece quando o servidor MUDA depois do backup: o disco E: sumiu, o
        usuario perdeu a permissao do Hyper-V, a pasta foi renomeada. O backup
        de ontem existe; o plano de hoje nao encontra mais nada.

        Esse e o caso mais perigoso que existe neste programa, porque parece
        saudavel de longe. Entao ele ganhou nome e vem antes de tudo.
    #>
    $enviouAntes = ($estado -and [int]$estado.Sucessos -gt 0)
    $planoVazio  = ($plano.Tarefas.Count -eq 0)
    $mudou = ($enviouAntes -and $planoVazio)

    $primeiroProblema = ''
    if ($plano.NaoProtegido.Count -gt 0) { $primeiroProblema = $plano.NaoProtegido[0] }
    $primeiroAviso = ''
    if ($plano.Avisos.Count -gt 0) { $primeiroAviso = $plano.Avisos[0] }

    if ($mudou) {
        $sp.Children.Add((FaixaVeredito 'erro' 'O servidor mudou desde a ultima copia' (
            'Ha backup na nuvem, mas HOJE nao ha nada sendo protegido aqui. ' +
            'O que estava configurado nao existe mais neste servidor - veja a lista abaixo. ' +
            'Enquanto isso nao for resolvido, o backup esta parado no tempo.'))) | Out-Null
    } elseif ($plano.NaoProtegido.Count -gt 0 -or $planoVazio) {
        $sp.Children.Add((FaixaVeredito 'erro' 'Este servidor nao esta protegido' `
            $primeiroProblema)) | Out-Null
    } elseif (-not $estado) {
        $sp.Children.Add((FaixaVeredito 'aviso' 'Nenhuma copia foi enviada ainda' `
            'O plano esta pronto. Va em "Executar agora" para a primeira copia.')) | Out-Null
    } elseif ([int]$estado.Falhas -gt 0) {
        $sp.Children.Add((FaixaVeredito 'erro' "$($estado.Falhas) item(ns) falharam na ultima copia" `
            "$($estado.Sucessos) enviado(s) com sucesso. Veja o Historico.")) | Out-Null
    } elseif ($plano.Avisos.Count -gt 0) {
        $sp.Children.Add((FaixaVeredito 'aviso' 'Protegido, com ressalvas' $primeiroAviso)) | Out-Null
    } else {
        $sp.Children.Add((FaixaVeredito 'ok' 'Este servidor esta protegido' `
            'Ultima copia externa conferida e enviada para a AWS.')) | Out-Null
    }

    # --- metricas ---
    <#
        Os quatro cartoes respondem quatro perguntas diferentes.

        Antes, dois deles contavam maquinas virtuais e bancos - numeros que
        num cartorio sem Hyper-V sao "0" e "0" para sempre, ocupando metade da
        faixa mais visivel da tela para nao dizer nada.

        Agora: quando foi, quanto do plano esta coberto, quando volta a rodar,
        e quanto subiu. Nenhum deles fica parado em zero por natureza.
    #>
    $q = DataOuNada $(if ($estado) { $estado.Terminou } else { $null })
    $bytesUltima = 0
    if ($estado) { foreach ($d in @($estado.Detalhes)) { if ($d.Sucesso) { $bytesUltima += [long]$d.Bytes } } }

    if ($q) {
        $horas = ((Get-Date) - $q).TotalHours
        $quando = if ($horas -lt 24) { "ha $([int]$horas) h" } else { "ha $([int]($horas/24)) dias" }
        $corQ = if ($mudou) { $Cores.Vermelho }
                elseif ($horas -le 24*35) { $Cores.Verde }
                elseif ($horas -le 24*60) { $Cores.Amarelo } else { $Cores.Vermelho }
        $dataQ = $q.ToString('dd/MM HH:mm')
        $volume = Tamanho $bytesUltima
    } elseif ($estado -and $estado.Rodando) {
        $quando = 'agora'; $corQ = $Cores.Azul; $dataQ = 'copia em andamento'; $volume = Tamanho $bytesUltima
    } else {
        $quando = 'nunca'; $corQ = $Cores.Vermelho; $dataQ = 'nenhuma copia'; $volume = '-'
    }

    $totalItens = $plano.Tarefas.Count + $plano.NaoProtegido.Count
    $enviados = 0
    if ($estado) { $enviados = [int]$estado.Sucessos }
    $corCob = if ($plano.NaoProtegido.Count -gt 0) { $Cores.Vermelho }
              elseif ($plano.Avisos.Count -gt 0) { $Cores.Amarelo } else { $Cores.Verde }

    $prox = ProximaExecucao
    if ($prox) {
        $faltam = ($prox - (Get-Date)).TotalHours
        $txtProx = if ($faltam -lt 1) { 'em minutos' }
                   elseif ($faltam -lt 24) { "em $([int]$faltam) h" }
                   else { "em $([int]($faltam/24)) dias" }
        $rodapeProx = $prox.ToString('dd/MM HH:mm')
        $corProx = $Cores.Azul
    } else {
        $txtProx = 'nao agendado'
        $rodapeProx = 'o backup nao roda sozinho'
        $corProx = $Cores.Vermelho
    }

    $sp.Children.Add((GradeDeCartoes @(
        (CartaoMetrica $Icones.Relogio $quando 'ULTIMA COPIA' $corQ $dataQ)
        (CartaoMetrica $Icones.Escudo "$($plano.Tarefas.Count)/$totalItens" 'ITENS NO PLANO' $corCob `
            $(if ($plano.NaoProtegido.Count -gt 0) { "$($plano.NaoProtegido.Count) fora do alcance" } else { 'tudo o que existe aqui' }))
        (CartaoMetrica $Icones.Play $txtProx 'PROXIMA COPIA' $corProx $rodapeProx)
        (CartaoMetrica $Icones.Nuvem $volume 'ENVIADO NA ULTIMA' $Cores.Verde 'S3 Glacier Deep Archive')
    ) 4)) | Out-Null

    # --- linha do tempo ---
    <#
        Preenchia-se metade da tela com preto e a pergunta mais comum ficava
        sem resposta: "isso vem rodando?". Uma coluna por execucao responde de
        relance, e a ALTURA e o volume - porque volume que despenca e o
        defeito que nao se anuncia, ja que a execucao continua "com sucesso".
    #>
    $execs = UltimasExecucoes $dados
    if ($execs.Count -gt 0) {
        $cT = NovoCartao
        $inT = New-Object Windows.Controls.StackPanel
        $comFalha = @($execs | Where-Object { $_.Falhou }).Count
        $subT = if ($comFalha -gt 0) { "$comFalha das ultimas $($execs.Count) com falha" }
                else { "as ultimas $($execs.Count) rodaram limpas" }
        $inT.Children.Add((NovoTexto 'ULTIMAS EXECUCOES' 11.5 $Cores.Texto2 'SemiBold')) | Out-Null
        $sT = NovoTexto "altura = volume enviado  -  $subT" 12 $Cores.Texto3
        $sT.Margin = '0,4,0,10'
        $inT.Children.Add($sT) | Out-Null
        $inT.Children.Add((LinhaDoTempo $execs)) | Out-Null
        $cT.Child = $inT
        $cT.Margin = '0,16,0,0'
        $sp.Children.Add($cT) | Out-Null
    }

    # --- o que esta no cofre ---
    <#
        A ROSCA SAIU, E ISSO E MELHORIA.

        Ela desenhava a mesma fracao do cartao "ITENS NO PLANO" logo acima -
        0% ao lado de 0/5, dois desenhos do mesmo numero na mesma tela - e
        cobrava por isso uma coluna de 300 pixels que ficava vazia embaixo do
        anel.

        Duas representacoes do mesmo dado nao sao redundancia inofensiva: elas
        competem pelo olho e nenhuma vence. O que faltava nesta tela nao era
        outro grafico da cobertura; era largura para a LISTA, que e onde estao
        os nomes que a pessoa precisa ler.

        A frase que a legenda da rosca carregava - "3 na nuvem, 0 no plano de
        hoje" - nao se perdeu: ela e importante demais e passou para o rodape
        do cartao de itens.
    #>
    $cLista = NovoCartao
    $cLista.Margin = '0,16,0,0'
    $spL = New-Object Windows.Controls.StackPanel
    $spL.Children.Add((NovoTexto 'O QUE ESTA NO COFRE' 11.5 $Cores.Texto2 'SemiBold')) | Out-Null
    $esp = New-Object Windows.Controls.Border; $esp.Height = 14
    $spL.Children.Add($esp) | Out-Null

    if ($plano.Tarefas.Count -eq 0) {
        $vazio = if ($mudou) {
            'Nada esta sendo protegido HOJE. O que ja subiu continua na nuvem e pode ser restaurado, mas nao esta mais sendo atualizado.'
        } else {
            'Nada foi identificado para proteger neste servidor.'
        }
        $spL.Children.Add((NovoTexto $vazio 13 $Cores.Texto3)) | Out-Null
    }
    foreach ($t in $plano.Tarefas) {
        $ult = $null
        if ($estado) { $ult = @($estado.Detalhes | Where-Object { $_.Nome -eq $t.Nome })[0] }
        $est = if (-not $ult) { 'neutro' } elseif (-not $ult.Sucesso) { 'erro' }
               elseif ($t.Porque -match 'CRASH') { 'aviso' } else { 'ok' }
        $dq = DataOuNada $(if ($ult) { $ult.Quando } else { $null })
        $qd = if ($dq) { $dq.ToString('dd/MM HH:mm') } else { 'nunca enviado' }
        $tm = if ($ult) { Tamanho ([long]$ult.Bytes) } else { '' }
        $spL.Children.Add((LinhaItem $t.Tipo $t.Nome $t.Porque $est $qd $tm)) | Out-Null
    }

    if ($plano.NaoProtegido.Count -gt 0) {
        $sepF = New-Object Windows.Controls.Border; $sepF.Height = 18
        $spL.Children.Add($sepF) | Out-Null
        $spL.Children.Add((NovoTexto 'FORA DO ALCANCE' 11.5 $Cores.Vermelho 'SemiBold')) | Out-Null
        foreach ($np in $plano.NaoProtegido) {
            $li = NovoTexto ('- ' + $np) 12.5 $Cores.Texto3
            $li.Margin = '0,8,0,0'
            $spL.Children.Add($li) | Out-Null
        }
    }

    # A frase da legenda da rosca vive aqui agora: quando ha copia na nuvem e
    # o plano de hoje esta vazio, os dois numeros precisam aparecer juntos -
    # senao um desmente o outro em silencio.
    if ($mudou) {
        $sepR = New-Object Windows.Controls.Border; $sepR.Height = 14
        $spL.Children.Add($sepR) | Out-Null
        $spL.Children.Add((NovoTexto "$enviados item(ns) na nuvem, 0 no plano de hoje" `
            12 $Cores.Amarelo)) | Out-Null
    }

    $cLista.Child = $spL
    $sp.Children.Add($cLista) | Out-Null

    # --- para onde vai ---
    <#
        A pergunta "para onde isso esta indo?" exigia trocar de tela. Sao tres
        dados que cabem numa linha, e sem eles o painel fala de backup sem
        dizer onde ele esta.
    #>
    $cfgP = LerConfiguracao (CaminhoDe $dados 'cofre.conf')
    if ($cfgP) {
        $cD = NovoCartao
        $cD.Margin = '0,16,0,0'
        $inD = New-Object Windows.Controls.StackPanel
        $inD.Children.Add((NovoTexto 'PARA ONDE VAI' 11.5 $Cores.Texto2 'SemiBold')) | Out-Null
        $temChave = Test-Path (CaminhoDe $dados 'rclone.conf')
        $inD.Children.Add((LinhaInfo 'Cartorio'  ([string]$cfgP.Cartorio))) | Out-Null
        $inD.Children.Add((LinhaInfo 'Servidor'  ([string]$ambiente.Maquina))) | Out-Null
        $inD.Children.Add((LinhaInfo 'Bucket'    "$($cfgP.Bucket)  ($($cfgP.Regiao))")) | Out-Null
        $inD.Children.Add((LinhaInfo 'Classe'    'S3 Glacier Deep Archive')) | Out-Null
        $inD.Children.Add((LinhaInfo 'Chave'     $(if ($temChave) { 'configurada neste servidor' } else { 'NAO CONFIGURADA - nada sai daqui' }) `
            $(if ($temChave) { $Cores.Verde } else { $Cores.Vermelho }))) | Out-Null
        $cD.Child = $inD
        $sp.Children.Add($cD) | Out-Null
    }

    return $sp
}

# ------------------------------------------------------------------------------
#  O QUE E PROTEGIDO
# ------------------------------------------------------------------------------
function TelaProtegido($ambiente, $plano, $estado, $nuvem, $janela, $aoConferir) {
    $sp = New-Object Windows.Controls.StackPanel

    $sp.Children.Add((FaixaVeredito 'info' "Estrategia: $($plano.Estrategia)" `
        'O Cofre olhou este servidor e decidiu sozinho o que proteger e como.')) | Out-Null

    if ($plano.Tarefas.Count -gt 0) {
        $sp.Children.Add((Secao 'No Cofre' "$($plano.Tarefas.Count) item(ns)")) | Out-Null
        $c = NovoCartao
        $inner = New-Object Windows.Controls.StackPanel
        foreach ($t in $plano.Tarefas) {
            $est = if ($t.Porque -match 'CRASH') { 'aviso' } else { 'ok' }
            $inner.Children.Add((LinhaItem $t.Tipo $t.Nome $t.Porque $est $t.Frequencia '')) | Out-Null
        }
        $c.Child = $inner
        $sp.Children.Add($c) | Out-Null
    }

    if ($plano.NaoProtegido.Count -gt 0) {
        $sp.Children.Add((Secao 'Nao protegido' 'Isto precisa ser resolvido')) | Out-Null
        $c = NovoCartao
        $inner = New-Object Windows.Controls.StackPanel
        foreach ($n in $plano.NaoProtegido) {
            $inner.Children.Add((LinhaItem 'outro' $n '' 'erro' '' '')) | Out-Null
        }
        $c.Child = $inner
        $sp.Children.Add($c) | Out-Null
    }

    # Decisao deliberada NAO usa vermelho. Vermelho que nao significa problema
    # treina o tecnico a ignorar vermelho, e no dia do vermelho de verdade ele
    # passa batido.
    if ($plano.PorDecisao.Count -gt 0) {
        $sp.Children.Add((Secao 'Fora do Cofre, de proposito' 'Nao e falha')) | Out-Null
        $c = NovoCartao
        $inner = New-Object Windows.Controls.StackPanel
        foreach ($d in $plano.PorDecisao) {
            $inner.Children.Add((LinhaItem 'outro' $d '' 'neutro' '' '')) | Out-Null
        }
        $c.Child = $inner
        $sp.Children.Add($c) | Out-Null
    }

    if ($plano.Avisos.Count -gt 0) {
        $sp.Children.Add((Secao 'Para olhar' 'Funciona, mas alguem precisa ver')) | Out-Null
        $c = NovoCartao
        $inner = New-Object Windows.Controls.StackPanel
        foreach ($a in $plano.Avisos) {
            $inner.Children.Add((LinhaItem 'outro' $a '' 'aviso' '' '')) | Out-Null
        }
        $c.Child = $inner
        $sp.Children.Add($c) | Out-Null
    }

    # --- o servidor ---
    $sp.Children.Add((Secao 'Este servidor' '')) | Out-Null
    $c = NovoCartao
    $inner = New-Object Windows.Controls.StackPanel

    $inner.Children.Add((LinhaItem 'imagem' $ambiente.Maquina $ambiente.Windows `
        $(if ($ambiente.EhServer) { 'ok' } else { 'aviso' }) `
        $(if ($ambiente.EhServer) { 'Windows Server' } else { 'edicao client' }) '')) | Out-Null

    if ($ambiente.EhHost) {
        $inner.Children.Add((LinhaItem 'vm' 'Hyper-V' "$($ambiente.VMs.Count) maquina(s) virtual(is)" 'ok' '' '')) | Out-Null
    } else {
        $inner.Children.Add((LinhaItem 'vm' 'Hyper-V' $ambiente.HyperVNota 'neutro' '' '')) | Out-Null
    }

    foreach ($d in @($ambiente.Discos | Where-Object { $_.ServeParaTrabalho })) {
        $usado = 1 - ($d.LivreBytes / $d.TotalBytes)
        $corD = if ($usado -gt 0.9) { $Cores.Vermelho } elseif ($usado -gt 0.75) { $Cores.Amarelo } else { $Cores.Verde }
        $inner.Children.Add((LinhaItem 'disco' "Disco $($d.Unidade):" `
            "$(Tamanho $d.LivreBytes) livres de $(Tamanho $d.TotalBytes)" `
            $(if ($usado -gt 0.9) { 'erro' } elseif ($usado -gt 0.75) { 'aviso' } else { 'ok' }) `
            ("{0:N0}% usado" -f ($usado * 100)) '')) | Out-Null
    }

    $c.Child = $inner
    $sp.Children.Add($c) | Out-Null


    <#
        A CONFERENCIA CONTRA A NUVEM.

        O resto desta tela mostra o que o programa PLANEJA proteger e o que
        ele ACHA que enviou - tudo lido do proprio estado.json. Se o agente
        errar, ele erra nos dois lugares ao mesmo tempo e ninguem descobre.

        Este bloco pergunta para a AWS. E a unica parte do programa que nao
        acredita no proprio relatorio.

        Listar nao custa resgate: nome, tamanho e data vem do indice, e o
        objeto continua congelado. Da para conferir todo dia de graca.
    #>
    $sp.Children.Add((Secao 'Conferido na nuvem' 'Lido da AWS, e nao do relatorio deste programa')) | Out-Null
    $cN = NovoCartao
    $inN = New-Object Windows.Controls.StackPanel

    if ($null -eq $nuvem) {
        $inN.Children.Add((NovoTexto (
            'Ainda nao conferi. O botao abaixo le o bucket e compara, item por item, ' +
            'com o que deveria estar la.') 13 $Cores.Texto2)) | Out-Null
        $bN = NovoBotao 'Conferir na nuvem agora' $Icones.Nuvem $true $janela
        $bN.HorizontalAlignment = 'Left'
        $bN.Margin = '0,14,0,0'
        $bN.Add_Click({ & $aoConferir }.GetNewClosure())
        $inN.Children.Add($bN) | Out-Null

    } elseif ($nuvem.Erro) {
        $inN.Children.Add((NovoTexto ('Nao consegui ler o Cofre na AWS: ' + $nuvem.Erro) 13 $Cores.Vermelho)) | Out-Null
        $bN = NovoBotao 'Tentar de novo' $Icones.Nuvem $false $janela
        $bN.HorizontalAlignment = 'Left'
        $bN.Margin = '0,14,0,0'
        $bN.Add_Click({ & $aoConferir }.GetNewClosure())
        $inN.Children.Add($bN) | Out-Null

    } else {
        $ruins = @($nuvem.Itens | Where-Object { $_.Estado -ne 'ok' }).Count
        $vered = if ($ruins -eq 0) {
            "tudo o que deveria estar la esta la - $($nuvem.Lidos) arquivo(s), $(Tamanho $nuvem.TotalBytes)"
        } else {
            "$ruins item(ns) precisam de atencao - $($nuvem.Lidos) arquivo(s) na nuvem, $(Tamanho $nuvem.TotalBytes)"
        }
        $inN.Children.Add((NovoTexto $vered 13 $(if ($ruins -eq 0) { $Cores.Verde } else { $Cores.Amarelo }) 'SemiBold')) | Out-Null

        foreach ($i in $nuvem.Itens) {
            $rot = if ($i.UltimaData) { $i.UltimaData } else { '' }
            $tam = if ($i.Bytes -gt 0) { Tamanho $i.Bytes } else { '' }
            $inN.Children.Add((LinhaItem $i.Tipo "$($i.Disco) / $($i.Nome)" $i.Frase $i.Estado $rot $tam)) | Out-Null
        }

        $bN = NovoBotao 'Conferir de novo' $Icones.Nuvem $false $janela
        $bN.HorizontalAlignment = 'Left'
        $bN.Margin = '0,16,0,0'
        $bN.Add_Click({ & $aoConferir }.GetNewClosure())
        $inN.Children.Add($bN) | Out-Null
    }

    $cN.Child = $inN
    $sp.Children.Add($cN) | Out-Null
    return $sp
}

# ------------------------------------------------------------------------------
#  EXECUTAR AGORA
# ------------------------------------------------------------------------------
function TelaExecutar($ambiente, $plano, $estado, $aoClicar) {
    $sp = New-Object Windows.Controls.StackPanel

    $rodando = ($estado -and $estado.Rodando)

    if ($rodando) {
        $sp.Children.Add((FaixaVeredito 'info' "$($estado.EtapaAtual)" $estado.ItemAtual)) | Out-Null

        $c = NovoCartao
        $inner = New-Object Windows.Controls.StackPanel
        $inner.Children.Add((NovoTexto 'PROGRESSO' 11.5 $Cores.Texto2 'SemiBold')) | Out-Null

        $b = Barra ($estado.Progresso / 100) $Cores.Azul 9
        $b.Margin = '0,14,0,10'
        $inner.Children.Add($b) | Out-Null

        $inner.Children.Add((NovoTexto "$($estado.Progresso)%  -  $($estado.Sucessos) de $($estado.Itens) concluidos" `
            12.5 $Cores.Texto2)) | Out-Null

        $aviso = NovoTexto ('Pode fechar esta janela: quem trabalha e o motor, e ele continua sozinho. ' +
                            'Ao reabrir, a janela mostra onde parou.') 12 $Cores.Texto3
        $aviso.Margin = '0,14,0,0'
        $inner.Children.Add($aviso) | Out-Null

        $c.Child = $inner
        $sp.Children.Add($c) | Out-Null

    } else {
        $sp.Children.Add((FaixaVeredito 'info' 'Pronto para executar' `
            "$($plano.Tarefas.Count) item(ns) serao protegidos, conferidos, cifrados e enviados.")) | Out-Null

        $c = NovoCartao
        $inner = New-Object Windows.Controls.StackPanel
        $inner.Children.Add((NovoTexto 'O QUE VAI ACONTECER, EM ORDEM' 11.5 $Cores.Texto2 'SemiBold')) | Out-Null

        $passos = @(
            @{ I = $Icones.Maquina;  T = '1. Copia consistente';   D = 'Export-VM com production checkpoint, wbadmin, gbak ou BACKUP DATABASE - conforme o item' }
            @{ I = $Icones.Certo;    T = '2. Conferencia';         D = 'Compare-VM, restauracao de teste do banco, e impressao digital SHA-256 de cada arquivo' }
            @{ I = $Icones.Chave;    T = '3. Criptografia';        D = 'AES-256 neste servidor, antes de qualquer byte sair. A AWS recebe conteudo e nomes cifrados' }
            @{ I = $Icones.Nuvem;    T = '4. Envio';               D = 'rclone direto para o S3 Glacier Deep Archive, retomando de onde parar se o link cair' }
            @{ I = $Icones.Escudo;   T = '5. Conferencia final';   D = 'Lista o destino e confirma que chegou tudo, sem precisar descongelar nada' }
        )
        foreach ($p in $passos) {
            $linha = New-Object Windows.Controls.Grid
            $linha.Margin = '0,13,0,0'
            $ca = New-Object Windows.Controls.ColumnDefinition; $ca.Width = 'Auto'
            $cb = New-Object Windows.Controls.ColumnDefinition; $cb.Width = '*'
            $linha.ColumnDefinitions.Add($ca) | Out-Null
            $linha.ColumnDefinitions.Add($cb) | Out-Null

            $ic = NovoIcone $p.I 17 $Cores.Azul
            $ic.Margin = '0,0,15,0'
            $ic.VerticalAlignment = 'Top'
            [Windows.Controls.Grid]::SetColumn($ic, 0)
            $linha.Children.Add($ic) | Out-Null

            $txt = New-Object Windows.Controls.StackPanel
            $txt.Children.Add((NovoTexto $p.T 13.5 $Cores.Texto 'SemiBold')) | Out-Null
            $d = NovoTexto $p.D 12 $Cores.Texto3
            $d.Margin = '0,3,0,0'
            $txt.Children.Add($d) | Out-Null
            [Windows.Controls.Grid]::SetColumn($txt, 1)
            $linha.Children.Add($txt) | Out-Null

            $inner.Children.Add($linha) | Out-Null
        }
        $c.Child = $inner
        $sp.Children.Add($c) | Out-Null

        $botoes = New-Object Windows.Controls.StackPanel
        $botoes.Orientation = 'Horizontal'
        $botoes.Margin = '0,20,0,0'

        $b1 = New-Object Windows.Controls.Button
        $b1.Content = 'Executar tudo agora'
        $b1.Tag = [string]$Icones.Play
        $b1.Style = $janela.FindResource('BotaoPrimario')
        $b1.IsEnabled = ($plano.Tarefas.Count -gt 0)
        $b1.Add_Click({ & $aoClicar 'tudo' }.GetNewClosure())
        $botoes.Children.Add($b1) | Out-Null

        $b2 = New-Object Windows.Controls.Button
        $b2.Content = 'Somente os bancos'
        $b2.Tag = [string]$Icones.Banco
        $b2.Style = $janela.FindResource('BotaoSecundario')
        $b2.Margin = '12,0,0,0'
        $b2.IsEnabled = (@($plano.Tarefas | Where-Object { $_.Tipo -in @('firebird','sqlserver') }).Count -gt 0)
        $b2.Add_Click({ & $aoClicar 'bancos' }.GetNewClosure())
        $botoes.Children.Add($b2) | Out-Null

        $sp.Children.Add($botoes) | Out-Null
    }

    return $sp
}

# ------------------------------------------------------------------------------
#  HISTORICO
# ------------------------------------------------------------------------------
function TelaHistorico($raiz) {
    $sp = New-Object Windows.Controls.StackPanel
    $pasta = CaminhoDe $dados 'historico'

    $execucoes = @()
    if (Test-Path $pasta) {
        foreach ($f in @(Get-ChildItem $pasta -Filter '*.json' -ErrorAction SilentlyContinue |
                         Sort-Object Name -Descending | Select-Object -First 40)) {
            try { $execucoes += (Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { }
        }
    }

    if ($execucoes.Count -eq 0) {
        $sp.Children.Add((FaixaVeredito 'aviso' 'Ainda nao ha historico' `
            'Cada execucao do Cofre fica registrada aqui, com o que foi enviado e o que falhou.')) | Out-Null
        return $sp
    }

    <#
        O banner conta o que a lista conta.

        Ele contava por 'Resultado', que e um campo separado; a lista conta por
        'Falhas'. Um registro sem Resultado - execucao interrompida, arquivo de
        versao antiga - fazia o banner dizer "0 de 12 sem falha" em laranja
        com doze linhas verdes logo abaixo.

        Mesmo defeito do Painel: dois numeros verdadeiros que juntos nao
        querem dizer nada. Aqui os dois passam a sair da mesma fonte.
    #>
    $ok = @($execucoes | Where-Object { [int]$_.Falhas -eq 0 }).Count
    $sp.Children.Add((FaixaVeredito $(if ($ok -eq $execucoes.Count) { 'ok' } else { 'aviso' }) `
        "$ok de $($execucoes.Count) execucoes sem falha" `
        "As $($execucoes.Count) mais recentes.")) | Out-Null
    $c = NovoCartao
    $inner = New-Object Windows.Controls.StackPanel
    foreach ($e in $execucoes) {
        $est = switch ($e.Resultado) {
            'sucesso' { 'ok' }
            'parcial' { 'aviso' }
            'falhou'  { 'erro' }
            default   { 'neutro' }
        }
        $bytes = 0
        foreach ($d in @($e.Detalhes)) { if ($d.Sucesso) { $bytes += [long]$d.Bytes } }
        $quando = ''
        $dt = DataOuNada $e.Terminou
        if ($dt) { $quando = $dt.ToString('dd/MM/yyyy HH:mm') }
        $inner.Children.Add((LinhaItem 'outro' $quando `
            "$($e.Sucessos) enviado(s), $($e.Falhas) com problema" `
            $est $e.Resultado (Tamanho $bytes))) | Out-Null
    }
    $c.Child = $inner
    $sp.Children.Add($c) | Out-Null

    return $sp
}

# ------------------------------------------------------------------------------
#  RESTAURAR
#
#  A tela que existe para o pior dia do cartorio. Tudo aqui e escrito partindo
#  do principio de que quem esta lendo esta com pressa e nervoso.
# ------------------------------------------------------------------------------
function TelaRestaurar($config, $pontos, $erroListagem, $janela, $aoAgir) {
    $sp = New-Object Windows.Controls.StackPanel

    if (-not $config) {
        $sp.Children.Add((FaixaVeredito 'aviso' 'Este servidor ainda nao foi configurado' `
            'Sem destino configurado nao ha o que restaurar. Va em "Destino na nuvem".')) | Out-Null
        return $sp
    }

    # O aviso do tempo vem ANTES da lista, de proposito. E a informacao que
    # muda o que a pessoa vai fazer nos proximos minutos.
    $sp.Children.Add((BlocoAviso 'aviso' (
        'Os dados estao no S3 Glacier Deep Archive. Antes de baixar qualquer coisa e preciso ' +
        'PEDIR o descongelamento e ESPERAR: ate 48 horas no modo economico, ate 12 horas no ' +
        'modo rapido. Isso nao tem como acelerar. Peca assim que souber que vai precisar, ' +
        'mesmo antes de decidir o que fazer.'))) | Out-Null

    if ($erroListagem) {
        $sp.Children.Add((FaixaVeredito 'erro' 'Nao consegui ler o Cofre na AWS' $erroListagem)) | Out-Null
        return $sp
    }

    if (-not $pontos -or $pontos.Count -eq 0) {
        $sp.Children.Add((FaixaVeredito 'aviso' 'Nao ha nenhum ponto de recuperacao' `
            'Nenhuma copia foi enviada para a AWS ainda.')) | Out-Null
        return $sp
    }

    $sp.Children.Add((FaixaVeredito 'ok' "$($pontos.Count) ponto(s) de recuperacao" `
        'Listar nao custa nada: le so os metadados, sem descongelar.')) | Out-Null

    $sp.Children.Add((Secao 'Pontos disponiveis' 'Do mais recente para o mais antigo')) | Out-Null

    $c = NovoCartao
    $inner = New-Object Windows.Controls.StackPanel

    foreach ($p in $pontos) {
        $b = New-Object Windows.Controls.Border
        $b.Background = Pincel $Cores.CartaoAlto
        $b.CornerRadius = 8
        $b.Padding = '16,13'
        $b.Margin = '0,0,0,8'

        $g = New-Object Windows.Controls.Grid
        $ca = New-Object Windows.Controls.ColumnDefinition; $ca.Width = '*'
        $cb = New-Object Windows.Controls.ColumnDefinition; $cb.Width = 'Auto'
        $g.ColumnDefinitions.Add($ca) | Out-Null
        $g.ColumnDefinitions.Add($cb) | Out-Null

        $txt = New-Object Windows.Controls.StackPanel
        $txt.VerticalAlignment = 'Center'
        $txt.Children.Add((NovoTexto $p.Rotulo 13.5 $Cores.Texto 'SemiBold')) | Out-Null
        $d = NovoTexto $p.Caminho 11 $Cores.Texto3
        $d.Margin = '0,3,0,0'
        $txt.Children.Add($d) | Out-Null
        [Windows.Controls.Grid]::SetColumn($txt, 0)
        $g.Children.Add($txt) | Out-Null

        $bots = New-Object Windows.Controls.StackPanel
        $bots.Orientation = 'Horizontal'

        $caminhoDeste = $p.Caminho

        $b1 = NovoBotao 'Descongelar' $Icones.Relogio $false $janela
        $b1.Height = 34
        $b1.Add_Click({ & $aoAgir 'descongelar' $caminhoDeste }.GetNewClosure())
        $bots.Children.Add($b1) | Out-Null

        $b2 = NovoBotao 'Situacao' $Icones.Info $false $janela
        $b2.Height = 34
        $b2.Margin = '8,0,0,0'
        $b2.Add_Click({ & $aoAgir 'situacao' $caminhoDeste }.GetNewClosure())
        $bots.Children.Add($b2) | Out-Null

        $b3 = NovoBotao 'Baixar' $Icones.Baixar $true $janela
        $b3.Height = 34
        $b3.Margin = '8,0,0,0'
        $b3.Add_Click({ & $aoAgir 'baixar' $caminhoDeste }.GetNewClosure())
        $bots.Children.Add($b3) | Out-Null

        [Windows.Controls.Grid]::SetColumn($bots, 1)
        $g.Children.Add($bots) | Out-Null

        $b.Child = $g
        $inner.Children.Add($b) | Out-Null
    }

    $c.Child = $inner
    $sp.Children.Add($c) | Out-Null

    $sp.Children.Add((BlocoAviso 'info' (
        'Depois de baixar, o Cofre confere CADA ARQUIVO contra a impressao digital gravada no ' +
        'dia do backup. So confie no que voltou se aparecer RECUPERACAO CONFERIDA.'))) | Out-Null

    return $sp
}

# ------------------------------------------------------------------------------
#  DESTINO NA NUVEM
# ------------------------------------------------------------------------------
function TelaDestino($config, $temRclone, $janela, $aoTestar) {
    $sp = New-Object Windows.Controls.StackPanel

    if (-not $config) {
        $sp.Children.Add((FaixaVeredito 'aviso' 'Este servidor ainda nao foi configurado' `
            'Clique em "Configurar agora" no Painel, ou rode o CONFIGURAR.bat.')) | Out-Null
        $sp.Children.Add((BlocoAviso 'info' (
            'A configuracao e feita pelo instalador, e nao por esta tela, porque envolve ' +
            'gerar a chave de criptografia - e a chave so pode ser gerada uma vez, com a ' +
            'confirmacao de que foi guardada fora do cartorio.'))) | Out-Null
        return $sp
    }

    $sp.Children.Add((FaixaVeredito $(if ($temRclone) { 'ok' } else { 'erro' }) `
        "Destino: $($config.Bucket)" `
        $(if ($temRclone) { "Regiao $($config.Regiao) - S3 Glacier Deep Archive" }
          else { 'O rclone nao esta instalado nesta pasta.' }))) | Out-Null

    $sp.Children.Add((Secao 'Configuracao atual' '')) | Out-Null
    $c = NovoCartao
    $inner = New-Object Windows.Controls.StackPanel
    $inner.Children.Add((LinhaInfo 'Cartorio'          $config.Cartorio)) | Out-Null
    $inner.Children.Add((LinhaInfo 'Bucket'            $config.Bucket)) | Out-Null
    $inner.Children.Add((LinhaInfo 'Regiao'            $config.Regiao)) | Out-Null
    $inner.Children.Add((LinhaInfo 'Classe'            'DEEP_ARCHIVE (gravada no envio, sem regra de ciclo de vida)')) | Out-Null
    $inner.Children.Add((LinhaInfo 'Area de trabalho'  $config.PastaDeTrabalho)) | Out-Null
    $inner.Children.Add((LinhaInfo 'Criptografia'      'AES-256 neste servidor, antes de sair' $Cores.Verde)) | Out-Null
    $c.Child = $inner
    $sp.Children.Add($c) | Out-Null

    $sp.Children.Add((Secao 'Testar' 'Sobe 8 MB de verdade, confere que chegou, e apaga')) | Out-Null
    $bt = NovoBotao 'Testar conexao e medir o link' $Icones.Nuvem $true $janela
    $bt.HorizontalAlignment = 'Left'
    $bt.Add_Click({ & $aoTestar }.GetNewClosure())
    $sp.Children.Add($bt) | Out-Null

    $sp.Children.Add((BlocoAviso 'info' (
        'Por que Deep Archive direto, e nao regra de ciclo de vida: a regra do S3 filtra por ' +
        'prefixo, nao por final de nome. Com ela, tudo congela junto - inclusive os indices - ' +
        'e recuperar um arquivo de 10 KB exigiria descongelar o repositorio inteiro. ' +
        'Gravando a classe no proprio envio, cada copia e independente.'))) | Out-Null

    return $sp
}

# ------------------------------------------------------------------------------
#  CHAVE
# ------------------------------------------------------------------------------
function TelaChave($config, $temRcloneConf, $janela) {
    $sp = New-Object Windows.Controls.StackPanel

    if (-not $temRcloneConf) {
        $sp.Children.Add((FaixaVeredito 'erro' 'Nao ha chave neste servidor' `
            'Sem chave o Cofre nao envia nada. Rode o CONFIGURAR.bat.')) | Out-Null
        return $sp
    }

    $sp.Children.Add((FaixaVeredito 'ok' 'A chave esta configurada neste servidor' `
        'Tudo e cifrado aqui, antes de sair. A AWS recebe conteudo e nomes cifrados.')) | Out-Null

    # O texto mais importante do programa inteiro.
    $sp.Children.Add((BlocoAviso 'perigo' (
        'SEM A CHAVE, O QUE ESTA NA AWS E LIXO IRRECUPERAVEL. Nem a CH.Com, nem a Amazon, ' +
        'nem quem tiver a senha da conta consegue ler. Se a chave existir SO neste servidor ' +
        'e este servidor for destruido - que e exatamente o cenario para o qual o Cofre ' +
        'existe - o backup morre junto. Nao ha suporte que resolva.'))) | Out-Null

    $sp.Children.Add((Secao 'Onde a chave precisa estar' 'Tres lugares, e um deles fora do cartorio')) | Out-Null

    $c = NovoCartao
    $inner = New-Object Windows.Controls.StackPanel
    $lugares = @(
        @{ T = 'Neste servidor';                D = 'em rclone.conf, com acesso so para administradores'; E = 'ok' }
        @{ T = 'No cofre de senhas da CH.Com';  D = 'fora da cidade, se possivel';                        E = 'aviso' }
        @{ T = 'Em papel, envelope lacrado';    D = 'gerado pelo instalador, para imprimir e guardar';     E = 'aviso' }
    )
    foreach ($l in $lugares) {
        $inner.Children.Add((LinhaItem 'outro' $l.T $l.D $l.E '' '')) | Out-Null
    }
    $c.Child = $inner
    $sp.Children.Add($c) | Out-Null

    $sp.Children.Add((BlocoAviso 'aviso' (
        'O Cofre nao mostra a chave nesta tela de proposito. Uma chave na tela vira print, ' +
        'e print vira WhatsApp. Ela foi gravada em papel no momento da instalacao - se essa ' +
        'copia se perdeu, o caminho e reinstalar e enviar tudo de novo.'))) | Out-Null

    return $sp
}

# ------------------------------------------------------------------------------
#  CONFIGURACAO
# ------------------------------------------------------------------------------
function TelaConfiguracao($config, $tarefas, $janela, $aoSalvar) {
    $sp = New-Object Windows.Controls.StackPanel

    if (-not $config) {
        $sp.Children.Add((FaixaVeredito 'aviso' 'Nao ha configuracao neste servidor' `
            'Rode o CONFIGURAR.bat.')) | Out-Null
        return $sp
    }

    $sp.Children.Add((Secao 'Agendamento' 'O motor decide o que esta na hora; a tarefa so o acorda')) | Out-Null

    $c = NovoCartao
    $inner = New-Object Windows.Controls.StackPanel

    if ($tarefas -and $tarefas.Count -gt 0) {
        foreach ($t in $tarefas) {
            $est = if ($t.Estado -eq 'Ready' -or $t.Estado -eq 'Running') { 'ok' } else { 'aviso' }
            $inner.Children.Add((LinhaItem 'outro' $t.Nome $t.Quando $est $t.Estado '')) | Out-Null
        }
    } else {
        $inner.Children.Add((LinhaItem 'outro' 'Nenhuma tarefa agendada' `
            'O Cofre nao vai rodar sozinho. Rode o CONFIGURAR.bat.' 'erro' '' '')) | Out-Null
    }

    $c.Child = $inner
    $sp.Children.Add($c) | Out-Null

    $sp.Children.Add((BlocoAviso 'info' (
        'Bancos rodam todo dia porque sao pequenos e mudam todo dia. VMs e imagem de servidor ' +
        'rodam uma vez por mes, no sabado a noite: sao grandes, o que se protege e o SERVIDOR, ' +
        'e a rodada longa nao pode disputar a madrugada de dia util com o backup local.'))) | Out-Null

    $sp.Children.Add((Secao 'Banco Firebird' 'Caminho do .fdb que o gbak vai ler')) | Out-Null
    $campo = CampoTexto 'Caminho do banco' $config.BancoFirebird 'Ex: C:\Sistema\dados\CARTORIO.FDB'
    $c2 = NovoCartao
    $c2.Child = $campo.Elemento
    $sp.Children.Add($c2) | Out-Null

    $bs = NovoBotao 'Salvar' $Icones.Certo $true $janela
    $bs.HorizontalAlignment = 'Left'
    $bs.Margin = '0,4,0,0'
    $caixa = $campo.Caixa
    $bs.Add_Click({ & $aoSalvar $caixa.Text }.GetNewClosure())
    $sp.Children.Add($bs) | Out-Null

    $sp.Children.Add((Secao 'Este servidor' '')) | Out-Null
    $c3 = NovoCartao
    $i3 = New-Object Windows.Controls.StackPanel
    $i3.Children.Add((LinhaInfo 'Cartorio'         $config.Cartorio)) | Out-Null
    $i3.Children.Add((LinhaInfo 'Area de trabalho' $config.PastaDeTrabalho)) | Out-Null
    $i3.Children.Add((LinhaInfo 'Copia local'      $(if ($config.ManterCopiaLocal) { 'mantida apos o envio' } else { 'apagada apos o envio' }))) | Out-Null
    $i3.Children.Add((LinhaInfo 'Painel'           $(if ($config.UrlPainel) { $config.UrlPainel } else { 'nao configurado' }))) | Out-Null
    $c3.Child = $i3
    $sp.Children.Add($c3) | Out-Null

    return $sp
}

<#
    Le os pontos de recuperacao da AWS.

    Fica aqui, e nao no arquivo da janela, porque e leitura de dados e nao
    desenho de tela. A listagem le so metadados: nao descongela nada e nao
    custa resgate.
#>
function LerPontosDeRecuperacao([string]$raiz, $config) {
    $r = [PSCustomObject]@{ Pontos = @(); Erro = $null }

    $rclone = CaminhoDoRclone $raiz
    $conf = CaminhoDe $dados 'rclone.conf'
    if (-not $rclone) { $r.Erro = 'o rclone nao esta instalado nesta pasta.'; return $r }
    if (-not (Test-Path $conf)) { $r.Erro = 'este servidor nao tem chave configurada.'; return $r }

    try {
        <#
            SO O QUE E DESTE CARTORIO.

            A primeira versao listava a raiz do bucket - ou seja, os 38
            cartorios - para depois jogar fora tudo o que nao era daqui. Duas
            coisas erradas nisso:

            A tela ficava lenta na proporcao do parque inteiro, quando o que
            ela precisa cabe num prefixo.

            E, pior, obrigava a credencial do cartorio a poder LISTAR o bucket
            inteiro. Isso derruba a unica tranca de verdade que existe entre
            um cartorio e os outros: a permissao do IAM. Menu escondido e
            conforto; prefixo no ListBucket e tranca.
        #>
        $meuPrefixo = "$($config.Remoto):$($config.Cartorio)"
        $exec = RodarRclone -Rclone $rclone -Argumentos @(
            'lsjson', $meuPrefixo, '--config', $conf, '--recursive', '--dirs-only')
        if ($exec.Codigo -ne 0) { throw $exec.Erro }

        $itens = LerListaDoRclone $exec.Saida
        foreach ($i in $itens) {
            # So as pastas terminadas em data sao pontos de recuperacao. As de
            # cima sao estrutura: maquina, disco, nome.
            $partes = $i.Path -split '/'
            $ultima = $partes[$partes.Count - 1]
            if ($ultima -notmatch '^\d{4}-\d{2}-\d{2}$') { continue }

            $nome = if ($partes.Count -ge 2) { $partes[$partes.Count - 2] } else { '' }
            $tipo = if ($partes.Count -ge 3) { $partes[$partes.Count - 3] } else { '' }
            $r.Pontos += [PSCustomObject]@{
                Caminho = "$($config.Cartorio)/$($i.Path)"
                Rotulo  = "$nome  -  $ultima"
                Tipo    = $tipo
                Data    = $ultima
            }
        }
        $r.Pontos = @($r.Pontos | Sort-Object Data -Descending)

    } catch {
        $r.Erro = $_.Exception.Message
    }
    return $r
}

# Lista as tarefas do Agendador que pertencem ao Cofre.
function LerTarefasAgendadas {
    $lista = @()
    try {
        foreach ($t in @(Get-ScheduledTask -TaskName 'CH.Com Cofre*' -ErrorAction SilentlyContinue)) {
            $info = $null
            try { $info = Get-ScheduledTaskInfo -TaskName $t.TaskName -ErrorAction SilentlyContinue } catch { }
            $quando = ''
            if ($info -and $info.NextRunTime) { $quando = 'proxima: ' + $info.NextRunTime.ToString('dd/MM/yyyy HH:mm') }
            $lista += [PSCustomObject]@{
                Nome = $t.TaskName
                Estado = [string]$t.State
                Quando = $quando
            }
        }
    } catch { }
    return $lista
}

# ------------------------------------------------------------------------------
#  TODOS OS CARTORIOS - o modo gerente
#
#  Substitui o painel-servidor. Le os estados direto do bucket: nenhum
#  servidor no meio, nada exposto na internet, nada para manter no ar.
# ------------------------------------------------------------------------------
function TelaParque($parque, $temConfig, $janela, $aoAtualizar, $aoConfigurar) {
    $sp = New-Object Windows.Controls.StackPanel

    <#
        AS TRES TELAS VAZIAS DESTA PAGINA.

        Esta e a PRIMEIRA tela que o gerente ve ao abrir o programa. Antes de
        haver cartorio publicando, ela era dois avisos e 80% de preto - e o
        primeiro deles mandava "configure o destino" sem dar nenhum caminho
        para configurar. Tela que manda fazer e nao deixa fazer e pior que tela
        vazia.

        Os tres estados vazios sao diferentes e cada um precisa dizer o seu:

          sem acesso      - falta credencial NESTE computador
          sem cartorio    - o acesso funciona, ninguem publicou ainda
          erro de leitura - o acesso existe e a AWS recusou

        Confundir os tres manda o gerente mexer no lugar errado.
    #>
    if (-not $temConfig) {
        $sp.Children.Add((FaixaVeredito 'aviso' 'Este computador ainda nao le o Cofre' `
            'Faltam as credenciais da AWS aqui. Nada foi perdido: os cartorios continuam enviando.')) | Out-Null

        $c = NovoCartao
        $c.Margin = '0,16,0,0'
        $in = New-Object Windows.Controls.StackPanel
        $in.Children.Add((NovoTexto 'O QUE FALTA, E O QUE NAO FALTA' 11.5 $Cores.Texto2 'SemiBold')) | Out-Null
        $e1 = New-Object Windows.Controls.Border; $e1.Height = 12
        $in.Children.Add($e1) | Out-Null
        $in.Children.Add((LinhaItem 'outro' 'Um usuario IAM so de leitura' `
            'aws/politica-gerente.json - s3:ListBucket e s3:GetObject no bucket inteiro' 'aviso' '' '')) | Out-Null
        $in.Children.Add((LinhaItem 'outro' 'As duas chaves neste computador' `
            'o assistente pede no passo 3 e grava so aqui' 'aviso' '' '')) | Out-Null
        $in.Children.Add((LinhaItem 'outro' 'NADA a instalar nos cartorios' `
            'eles ja publicam o estado sozinhos, ao lado do backup' 'ok' '' '')) | Out-Null
        $in.Children.Add((LinhaItem 'outro' 'NADA de servidor, dominio ou token' `
            'esta tela le o bucket direto, sem nada no meio' 'ok' '' '')) | Out-Null

        if ($aoConfigurar) {
            $b = NovoBotao 'Configurar o acesso agora' $Icones.Nuvem $true $janela
            $b.HorizontalAlignment = 'Left'
            $b.Margin = '0,18,0,0'
            $b.Add_Click({ & $aoConfigurar }.GetNewClosure())
            $in.Children.Add($b) | Out-Null
        }
        $c.Child = $in
        $sp.Children.Add($c) | Out-Null
        return $sp
    }

    if ($parque.Erro) {
        $sp.Children.Add((FaixaVeredito 'erro' 'O acesso existe, mas a AWS recusou a leitura' $parque.Erro)) | Out-Null
        $sp.Children.Add((BlocoAviso 'aviso' (
            'Isto NAO e falta de configuracao - as credenciais estao aqui e foram usadas. ' +
            'O caso mais comum e a politica do usuario IAM sem s3:ListBucket no bucket inteiro. ' +
            'Confira em aws/politica-gerente.json.'))) | Out-Null
        return $sp
    }

    $resumos = @($parque.Servidores | ForEach-Object { ResumirServidor $_ })

    if ($resumos.Count -eq 0) {
        $sp.Children.Add((FaixaVeredito 'aviso' 'O Cofre respondeu, e esta vazio' `
            'A leitura funcionou. Nenhum cartorio publicou estado ainda.')) | Out-Null
        $c2 = NovoCartao
        $c2.Margin = '0,16,0,0'
        $in2 = New-Object Windows.Controls.StackPanel
        $in2.Children.Add((NovoTexto 'O QUE FAZ UM CARTORIO APARECER AQUI' 11.5 $Cores.Texto2 'SemiBold')) | Out-Null
        $e2 = New-Object Windows.Controls.Border; $e2.Height = 12
        $in2.Children.Add($e2) | Out-Null
        $in2.Children.Add((LinhaItem 'outro' '1. O Cofre instalado no servidor dele' `
            'CH.Com-Cofre-Instalador.exe, dois cliques' 'neutro' '' '')) | Out-Null
        $in2.Children.Add((LinhaItem 'outro' '2. O assistente concluido ate o fim' `
            'e no passo do teste que a credencial e provada' 'neutro' '' '')) | Out-Null
        $in2.Children.Add((LinhaItem 'outro' '3. UMA copia terminada' `
            'o estado e publicado no fim da rodada - antes disso nao ha o que mostrar' 'neutro' '' '')) | Out-Null
        $c2.Child = $in2
        $sp.Children.Add($c2) | Out-Null
        return $sp
    }

    $comErro  = @($resumos | Where-Object { $_.Estado -eq 'erro' })
    $comAviso = @($resumos | Where-Object { $_.Estado -eq 'aviso' })

    <#
        O veredito conta os PROBLEMAS primeiro.

        Num parque de 50 cartorios, "48 em dia" e a informacao inutil: quem
        abre esta tela quer saber quais 2 precisam de alguem hoje.
    #>
    if ($comErro.Count -gt 0) {
        $sp.Children.Add((FaixaVeredito 'erro' `
            "$($comErro.Count) servidor(es) precisam de atencao AGORA" `
            (($comErro | ForEach-Object { "$($_.Cartorio)/$($_.Servidor)" }) -join '  -  '))) | Out-Null
    } elseif ($comAviso.Count -gt 0) {
        $sp.Children.Add((FaixaVeredito 'aviso' `
            "$($comAviso.Count) servidor(es) com ressalva" `
            'Nada parado, mas vale olhar.')) | Out-Null
    } else {
        $sp.Children.Add((FaixaVeredito 'ok' 'Todos os cartorios em dia' `
            "$($resumos.Count) servidor(es) reportando normalmente.")) | Out-Null
    }

    # --- os numeros ---
    $bytes = 0
    foreach ($r in $resumos) { $bytes += [long]$r.Bytes }
    $cartorios = @($resumos | ForEach-Object { $_.Cartorio } | Select-Object -Unique).Count

    $sp.Children.Add((GradeDeCartoes @(
        (CartaoMetrica $Icones.Escudo  "$cartorios" 'CARTORIOS' $Cores.Azul "$($resumos.Count) servidor(es)")
        (CartaoMetrica $Icones.Certo   "$(($resumos | Where-Object { $_.Estado -eq 'ok' }).Count)" 'EM DIA' $Cores.Verde 'dentro do prazo')
        (CartaoMetrica $Icones.Alerta  "$($comAviso.Count)" 'COM RESSALVA' $Cores.Amarelo 'funcionando, mas olhar')
        (CartaoMetrica $Icones.Erro    "$($comErro.Count)" 'PARADOS OU COM FALHA' $Cores.Vermelho 'precisam de alguem')
    ) 4)) | Out-Null

    # --- a lista, com os piores em cima ---
    $sp.Children.Add((Secao 'Servidores' 'Os que precisam de atencao aparecem primeiro')) | Out-Null

    $ordem = @{ 'erro' = 0; 'aviso' = 1; 'sem-dados' = 2; 'ok' = 3 }
    $ordenados = @($resumos | Sort-Object `
        @{ Expression = { $ordem[$_.Estado] } }, `
        @{ Expression = { $_.Cartorio } })

    $c = NovoCartao
    $inner = New-Object Windows.Controls.StackPanel
    foreach ($r in $ordenados) {
        $quando = if ($r.Quando) { $r.Quando.ToString('dd/MM HH:mm') } else { 'nunca' }
        $inner.Children.Add((LinhaItem 'imagem' "$($r.Cartorio)  /  $($r.Servidor)" `
            $r.Detalhe $r.Estado $quando $r.Frase)) | Out-Null
    }
    $c.Child = $inner
    $sp.Children.Add($c) | Out-Null

    $rodape = NovoTexto ("lido do bucket em " + $parque.LidoEm.ToString('dd/MM/yyyy HH:mm') +
                         "  -  sem servidor no meio") 11.5 $Cores.Texto3
    $rodape.Margin = '0,14,0,0'
    $sp.Children.Add($rodape) | Out-Null

    $bt = NovoBotao 'Atualizar do bucket' $Icones.Nuvem $false $janela
    $bt.HorizontalAlignment = 'Left'
    $bt.Margin = '0,12,0,0'
    $bt.Add_Click({ & $aoAtualizar }.GetNewClosure())
    $sp.Children.Add($bt) | Out-Null

    return $sp
}
