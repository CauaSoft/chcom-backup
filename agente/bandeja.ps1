<#
================================================================================
  CH.Com Cofre - icone ao lado do relogio

  Fica residente, olhando o estado.json, e avisa quando algo muda.

  POR QUE ISSO IMPORTA NUM CARTORIO

  Ninguem abre o programa de backup para conferir se esta tudo bem. A pessoa
  abre quando ja deu problema. O icone resolve isso ao contrario: ele esta
  sempre a vista, com a cor do estado, e quando algo falha ele fala primeiro.

  A COR NAO E ENFEITE
     verde     a ultima copia subiu e foi conferida
     azul      esta copiando agora
     amarelo   copiou, mas ha ressalva - ou faz tempo demais
     vermelho  falhou, ou nunca copiou

  ELE NAO FAZ BACKUP. Igual a janela: quem trabalha e o motor. Fechar a
  bandeja nao interrompe copia nenhuma.
================================================================================
#>

[CmdletBinding()]
param(
    # Nao entra no laco de mensagens. So monta tudo e sai - para dar para
    # conferir por codigo que o icone monta, sem prender o console.
    [switch]$NaoRodar
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $raiz 'modulos\comum.ps1')

# Onde ficam configuracao, estado e historico. NAO e a pasta do codigo:
# Program Files e somente leitura para quem nao e administrador.
$dados = PastaDeDados $raiz

$ArquivoEstado = CaminhoDe $dados 'estado.json'
$PastaMarca = CaminhoDe $raiz 'marca'

# ------------------------------------------------------------------------------
#  Icones
#
#  Um icone por estado, desenhado na hora: o icone da marca com um ponto
#  colorido no canto. Assim nao ha quatro arquivos .ico para manter em sincronia
#  com a marca - muda o logo, mudam os quatro.
# ------------------------------------------------------------------------------
$script:IconesPorEstado = @{}

function MontarIcone([System.Drawing.Color]$cor) {
    $lado = 32
    $bmp = New-Object System.Drawing.Bitmap($lado, $lado)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.SmoothingMode = 'AntiAlias'

        $base = CaminhoDe $PastaMarca 'logo-256.png'
        if (Test-Path $base) {
            $img = [System.Drawing.Image]::FromFile($base)
            try { $g.DrawImage($img, 0, 0, $lado, $lado) } finally { $img.Dispose() }
        }

        # O ponto de estado, com um anel escuro em volta para ele aparecer
        # tanto na barra clara quanto na escura.
        $d = 13
        $x = $lado - $d - 1
        $y = $lado - $d - 1

        $fundo = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 11, 15, 20))
        $g.FillEllipse($fundo, $x - 2, $y - 2, $d + 4, $d + 4)
        $fundo.Dispose()

        $pincel = New-Object System.Drawing.SolidBrush($cor)
        $g.FillEllipse($pincel, $x, $y, $d, $d)
        $pincel.Dispose()

    } finally { $g.Dispose() }

    # FromHandle nao copia: se o bitmap for descartado, o icone quebra. O
    # clone garante um icone que vive por conta propria.
    $h = $bmp.GetHicon()
    $icone = [System.Drawing.Icon]::FromHandle($h)
    $copia = $icone.Clone()
    $bmp.Dispose()
    return $copia
}

function IconeDe([string]$estado) {
    if (-not $script:IconesPorEstado.ContainsKey($estado)) {
        $cor = switch ($estado) {
            'ok'       { [System.Drawing.Color]::FromArgb(255, 46, 204, 113) }
            'copiando' { [System.Drawing.Color]::FromArgb(255, 30, 144, 255) }
            'aviso'    { [System.Drawing.Color]::FromArgb(255, 240, 166, 46) }
            default    { [System.Drawing.Color]::FromArgb(255, 255, 77, 90)  }
        }
        $script:IconesPorEstado[$estado] = MontarIcone $cor
    }
    return $script:IconesPorEstado[$estado]
}

# ------------------------------------------------------------------------------
#  Ler o estado e traduzir para cor e frase
# ------------------------------------------------------------------------------
function LerEstado {
    if (-not (Test-Path $ArquivoEstado)) { return $null }
    try { return (Get-Content $ArquivoEstado -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

<#
    Traduz o estado para o que aparece ao passar o mouse.

    O texto e limitado a 63 caracteres pelo Windows - acima disso o balao
    simplesmente nao aparece, sem erro nenhum. Por isso as frases sao curtas
    e o corte e explicito.
#>
function SituacaoAtual {
    $e = LerEstado

    if (-not $e) {
        return [PSCustomObject]@{ Estado = 'erro'; Texto = 'CH.Com Cofre - nenhuma copia enviada ainda' }
    }
    if ($e.Rodando) {
        $etapa = if ($e.EtapaAtual) { $e.EtapaAtual } else { 'copiando' }
        return [PSCustomObject]@{ Estado = 'copiando'; Texto = "CH.Com Cofre - $etapa ($($e.Progresso)%)" }
    }

    $quando = $null
    if ($e.Terminou) { try { $quando = [datetime]$e.Terminou } catch { } }
    $dias = if ($quando) { [int]((Get-Date) - $quando).TotalDays } else { 999 }

    if ($e.Falhas -gt 0) {
        return [PSCustomObject]@{ Estado = 'erro'; Texto = "CH.Com Cofre - $($e.Falhas) item(ns) falharam" }
    }
    # Mensal com folga: 35 dias ainda e normal, 60 ja e sinal de que parou.
    if ($dias -gt 60) {
        return [PSCustomObject]@{ Estado = 'erro'; Texto = "CH.Com Cofre - sem copia ha $dias dias" }
    }
    if ($dias -gt 35) {
        return [PSCustomObject]@{ Estado = 'aviso'; Texto = "CH.Com Cofre - ultima copia ha $dias dias" }
    }
    return [PSCustomObject]@{ Estado = 'ok'; Texto = "CH.Com Cofre - copia de $($quando.ToString('dd/MM'))" }
}

# ------------------------------------------------------------------------------
#  O icone
# ------------------------------------------------------------------------------
$icone = New-Object System.Windows.Forms.NotifyIcon
$icone.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip

function Item([string]$texto, [scriptblock]$acao) {
    $i = New-Object System.Windows.Forms.ToolStripMenuItem
    $i.Text = $texto
    $i.Add_Click($acao)
    return $i
}

$abrir = Item 'Abrir o CH.Com Cofre' {
    Start-Process powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass',
        '-WindowStyle','Hidden','-File', (Aspas (CaminhoDe (CaminhoDe $raiz 'interface') 'cofre-ui.ps1')))
}
$menu.Items.Add($abrir) | Out-Null

$copiar = Item 'Copiar agora' {
    Start-Process powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass',
        '-WindowStyle','Hidden','-File', (Aspas (CaminhoDe $raiz 'cofre.ps1')), '-Tudo')
}
$menu.Items.Add($copiar) | Out-Null

$diag = Item 'Diagnostico' {
    Start-Process powershell -ArgumentList @('-NoExit','-NoProfile','-ExecutionPolicy','Bypass',
        '-File', (Aspas (CaminhoDe $raiz 'diagnostico-cofre.ps1')))
}
$menu.Items.Add($diag) | Out-Null

$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

# "Fechar o icone", e nao "Sair": quem le "Sair" num programa de backup pensa
# que esta desligando o backup. O motor continua rodando pelo Agendador.
$sair = Item 'Fechar o icone (o backup continua)' {
    $icone.Visible = $false
    [System.Windows.Forms.Application]::Exit()
}
$menu.Items.Add($sair) | Out-Null

$icone.ContextMenuStrip = $menu
$icone.Add_DoubleClick({
    Start-Process powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass',
        '-WindowStyle','Hidden','-File', (Aspas (CaminhoDe (CaminhoDe $raiz 'interface') 'cofre-ui.ps1')))
})

# ------------------------------------------------------------------------------
#  Atualizar
#
#  A cada 30 segundos. Nao precisa ser mais rapido: quem quer acompanhar de
#  perto abre a janela, que atualiza a cada 2 segundos. Aqui o que importa e
#  a cor estar certa quando alguem olhar de passagem.
# ------------------------------------------------------------------------------
$script:UltimoEstado = ''

function Atualizar {
    $s = SituacaoAtual

    $icone.Icon = IconeDe $s.Estado
    # O Windows corta em 63 caracteres, e acima disso o balao nao aparece -
    # sem erro, so nao aparece.
    $t = $s.Texto
    if ($t.Length -gt 63) { $t = $t.Substring(0, 60) + '...' }
    $icone.Text = $t

    <#
        Avisar so na MUDANCA.

        Um balao a cada 30 segundos treina qualquer pessoa a ignorar balao. O
        aviso aparece quando o estado muda para pior - que e quando ele tem
        alguma chance de ser lido.
    #>
    if ($script:UltimoEstado -and $s.Estado -ne $script:UltimoEstado) {
        if ($s.Estado -eq 'erro') {
            $icone.BalloonTipIcon = 'Error'
            $icone.BalloonTipTitle = 'CH.Com Cofre'
            $icone.BalloonTipText = $s.Texto
            $icone.ShowBalloonTip(10000)
        } elseif ($s.Estado -eq 'ok' -and $script:UltimoEstado -eq 'copiando') {
            $icone.BalloonTipIcon = 'Info'
            $icone.BalloonTipTitle = 'CH.Com Cofre'
            $icone.BalloonTipText = 'Copia externa concluida e conferida.'
            $icone.ShowBalloonTip(6000)
        }
    }
    $script:UltimoEstado = $s.Estado
}

$relogio = New-Object System.Windows.Forms.Timer
$relogio.Interval = 30000
$relogio.Add_Tick({ Atualizar })

Atualizar
$relogio.Start()

if (-not $NaoRodar) {
    # Sem isto o processo termina e o icone some. O laco de mensagens tambem e
    # o que faz o menu e os cliques funcionarem.
    [System.Windows.Forms.Application]::Run()
    $icone.Visible = $false
    $icone.Dispose()
}
