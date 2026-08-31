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

function TelaPainel($ambiente, $plano, $estado, $temConfig, $janela, $aoConfigurar) {
    $sp = New-Object Windows.Controls.StackPanel

    # Sem configuracao, o veredito da lugar ao convite para configurar: dizer
    # "nao protegido" sem oferecer o caminho e so dar a noticia ruim.
    if (-not $temConfig) {
        $sp.Children.Add((BlocoConfigurar $janela $aoConfigurar)) | Out-Null
    }

    # --- veredito ---
    # Primeiro motivo da lista, quando houver. Escrito em duas linhas de
    # proposito: indexar o resultado de uma expressao entre parenteses exige
    # que nao haja espaco antes do colchete, e isso e um erro facil de fazer
    # e chato de achar.
    $primeiroProblema = ''
    if ($plano.NaoProtegido.Count -gt 0) { $primeiroProblema = $plano.NaoProtegido[0] }
    $primeiroAviso = ''
    if ($plano.Avisos.Count -gt 0) { $primeiroAviso = $plano.Avisos[0] }

    if ($plano.NaoProtegido.Count -gt 0 -or $plano.Tarefas.Count -eq 0) {
        $sp.Children.Add((FaixaVeredito 'erro' 'Este servidor nao esta protegido' `
            $primeiroProblema)) | Out-Null
    } elseif (-not $estado) {
        $sp.Children.Add((FaixaVeredito 'aviso' 'Nenhuma copia foi enviada ainda' `
            'O plano esta pronto. Va em "Executar agora" para a primeira copia.')) | Out-Null
    } elseif ($estado.Falhas -gt 0) {
        $sp.Children.Add((FaixaVeredito 'erro' "$($estado.Falhas) item(ns) falharam na ultima copia" `
            "$($estado.Sucessos) enviado(s) com sucesso. Veja o Historico.")) | Out-Null
    } elseif ($plano.Avisos.Count -gt 0) {
        $sp.Children.Add((FaixaVeredito 'aviso' 'Protegido, com ressalvas' $primeiroAviso)) | Out-Null
    } else {
        $sp.Children.Add((FaixaVeredito 'ok' 'Este servidor esta protegido' `
            'Ultima copia externa conferida e enviada para a AWS.')) | Out-Null
    }

    # --- metricas ---
    $qtdVM = @($plano.Tarefas | Where-Object { $_.Tipo -eq 'vm' }).Count
    $qtdBanco = @($plano.Tarefas | Where-Object { $_.Tipo -in @('firebird','sqlserver') }).Count
    <#
        $estado existir NAO significa que a copia terminou.

        Enquanto o motor trabalha, Terminou fica nulo - e [datetime]$null
        estoura. Estourando aqui, dentro do desenho, a janela inteira morre:
        era assim que a tela sumia quando alguem mandava fazer backup.
    #>
    $q = DataOuNada $(if ($estado) { $estado.Terminou } else { $null })
    if ($q) {
        $horas = ((Get-Date) - $q).TotalHours
        $quando = if ($horas -lt 24) { "ha $([int]$horas) h" } else { "ha $([int]($horas/24)) dias" }
        $corQ = if ($horas -le 24*35) { $Cores.Verde } elseif ($horas -le 24*60) { $Cores.Amarelo } else { $Cores.Vermelho }
        $dataQ = $q.ToString('dd/MM HH:mm')
        $bytes = 0
        foreach ($d in @($estado.Detalhes)) { if ($d.Sucesso) { $bytes += [long]$d.Bytes } }
        $volume = Tamanho $bytes
    } elseif ($estado -and $estado.Rodando) {
        $quando = 'agora'; $corQ = $Cores.Azul; $dataQ = 'copia em andamento'
        $bytes = 0
        foreach ($d in @($estado.Detalhes)) { if ($d.Sucesso) { $bytes += [long]$d.Bytes } }
        $volume = Tamanho $bytes
    } else {
        $quando = 'nunca'; $corQ = $Cores.Vermelho; $dataQ = 'nenhuma copia'; $volume = '-'
    }

    $sp.Children.Add((GradeDeCartoes @(
        (CartaoMetrica $Icones.Relogio  $quando 'ULTIMA COPIA'      $corQ        $dataQ)
        (CartaoMetrica $Icones.Maquina  "$qtdVM" 'MAQUINAS VIRTUAIS' $Cores.Azul  $(if ($qtdVM) { 'copia mensal' } else { 'nenhuma neste servidor' }))
        (CartaoMetrica $Icones.Banco    "$qtdBanco" 'BANCOS DE DADOS' $Cores.Azul $(if ($qtdBanco) { 'copia diaria' } else { 'nenhum neste servidor' }))
        (CartaoMetrica $Icones.Nuvem    $volume 'ENVIADO NA ULTIMA' $Cores.Verde 'S3 Glacier Deep Archive')
    ) 4)) | Out-Null

    # --- proporcao protegida + itens ---
    $g = New-Object Windows.Controls.Grid
    $g.Margin = '0,16,0,0'
    $ca = New-Object Windows.Controls.ColumnDefinition; $ca.Width = '300'
    $cb = New-Object Windows.Controls.ColumnDefinition; $cb.Width = '*'
    $g.ColumnDefinitions.Add($ca) | Out-Null
    $g.ColumnDefinitions.Add($cb) | Out-Null

    # rosca
    $cRosca = NovoCartao
    $cRosca.Margin = '0,0,14,0'
    $spR = New-Object Windows.Controls.StackPanel
    $spR.Children.Add((NovoTexto 'COBERTURA' 11.5 $Cores.Texto2 'SemiBold')) | Out-Null

    $totalItens = $plano.Tarefas.Count + $plano.NaoProtegido.Count
    $fracao = if ($totalItens -gt 0) { $plano.Tarefas.Count / $totalItens } else { 0 }
    $corR = if ($plano.NaoProtegido.Count -gt 0) { $Cores.Vermelho }
            elseif ($plano.Avisos.Count -gt 0) { $Cores.Amarelo } else { $Cores.Verde }

    $rosca = Rosca $fracao $corR ("{0:N0}%" -f ($fracao * 100)) 'protegido'
    $rosca.Margin = '0,16,0,10'
    $rosca.HorizontalAlignment = 'Center'
    $spR.Children.Add($rosca) | Out-Null

    $legenda = NovoTexto "$($plano.Tarefas.Count) de $totalItens itens no Cofre" 12 $Cores.Texto3
    $legenda.HorizontalAlignment = 'Center'
    $spR.Children.Add($legenda) | Out-Null

    $cRosca.Child = $spR
    [Windows.Controls.Grid]::SetColumn($cRosca, 0)
    $g.Children.Add($cRosca) | Out-Null

    # lista
    $cLista = NovoCartao
    $spL = New-Object Windows.Controls.StackPanel
    $spL.Children.Add((NovoTexto 'O QUE ESTA NO COFRE' 11.5 $Cores.Texto2 'SemiBold')) | Out-Null
    $esp = New-Object Windows.Controls.Border; $esp.Height = 14
    $spL.Children.Add($esp) | Out-Null

    if ($plano.Tarefas.Count -eq 0) {
        # "Nada foi identificado" e mentira quando existem itens NAO
        # PROTEGIDOS: eles foram identificados - e e justamente por isso que a
        # rosca ao lado diz "0 de 2". Visto num teste real, o texto e o numero
        # contavam historias diferentes na mesma tela.
        if ($plano.NaoProtegido.Count -gt 0) {
            $spL.Children.Add((NovoTexto ('Nada esta sendo enviado. Isto foi encontrado neste ' +
                'servidor, mas nao pode ser protegido:') 13 $Cores.Texto3)) | Out-Null
            foreach ($np in $plano.NaoProtegido) {
                $li = NovoTexto ('- ' + $np) 12.5 $Cores.Texto3
                $li.Margin = '0,8,0,0'
                $spL.Children.Add($li) | Out-Null
            }
        } else {
            $spL.Children.Add((NovoTexto 'Nada foi identificado para proteger neste servidor.' 13 $Cores.Texto3)) | Out-Null
        }
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

    $cLista.Child = $spL
    [Windows.Controls.Grid]::SetColumn($cLista, 1)
    $g.Children.Add($cLista) | Out-Null

    $sp.Children.Add($g) | Out-Null
    return $sp
}

# ------------------------------------------------------------------------------
#  O QUE E PROTEGIDO
# ------------------------------------------------------------------------------
function TelaProtegido($ambiente, $plano, $estado) {
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

    $ok = @($execucoes | Where-Object { $_.Resultado -eq 'sucesso' }).Count
    $sp.Children.Add((FaixaVeredito $(if ($ok -eq $execucoes.Count) { 'ok' } else { 'aviso' }) `
        "$ok de $($execucoes.Count) execucoes sem falha" 'As 40 execucoes mais recentes.')) | Out-Null

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
function TelaParque($parque, $temConfig, $janela, $aoAtualizar) {
    $sp = New-Object Windows.Controls.StackPanel

    if (-not $temConfig) {
        $sp.Children.Add((FaixaVeredito 'aviso' 'Este computador ainda nao tem acesso ao Cofre' `
            'Configure o destino na AWS para ver os cartorios.')) | Out-Null
        $sp.Children.Add((BlocoAviso 'info' (
            'O modo gerente le os estados que cada cartorio publica no bucket. Precisa da ' +
            'mesma credencial da AWS, com permissao de leitura - e nao precisa de nada ' +
            'instalado nos cartorios alem do proprio Cofre.'))) | Out-Null
        return $sp
    }

    if ($parque.Erro) {
        $sp.Children.Add((FaixaVeredito 'erro' 'Nao consegui ler o Cofre na AWS' $parque.Erro)) | Out-Null
        return $sp
    }

    $resumos = @($parque.Servidores | ForEach-Object { ResumirServidor $_ })

    if ($resumos.Count -eq 0) {
        $sp.Children.Add((FaixaVeredito 'aviso' 'Nenhum cartorio reportou ainda' `
            'Assim que um agente terminar uma copia, ele aparece aqui.')) | Out-Null
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
