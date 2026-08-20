<#
================================================================================
  CH.Com Backup - pastas de verificacao na AWS

  PARA QUE SERVE

  Abrir o console da AWS e ver so isto:

      duplicati-20260814T114711Z.dlist.zip.aes
      duplicati-b007acb694a7e4471b763a24ad333f86a.dblock.zip.aes
      duplicati-b00945f825b6a46988b7b56bc440d933b.dblock.zip.aes

  nao diz nada. Nao da para saber de que dia e cada coisa, nem se o backup de
  ontem chegou. Este script cria, no mesmo bucket, uma estrutura que se le:

      CARTORIO-X-VERIFICACAO/
          BACKUP-FULL/
              RESUMO.txt
          BACKUP-INCREMENTAL-14-08-2026/
              RESUMO.txt
          BACKUP-INCREMENTAL-15-08-2026/
              RESUMO.txt

  Cada RESUMO.txt diz, em portugues: a data, se deu certo, quanto subiu,
  quanto tempo levou, quanto tem guardado no total e quantas versoes existem.

  POR QUE AS PASTAS FICAM AO LADO, E NAO DENTRO DA PASTA DO BACKUP

  O Duplicati confere a lista de arquivos do destino a cada execucao. Arquivo
  que ele nao reconhece vira aviso, e em alguns casos ele pede reparo. Por
  isso nada e escrito dentro da pasta do backup: as pastas de verificacao vao
  para um prefixo IRMAO no mesmo bucket. O backup nao e tocado.

  POR QUE OS ARQUIVOS DE DADOS CONTINUAM COM AQUELE NOME

  Nao da para separar "os dados do dia 14" numa pasta so. O Duplicati quebra
  os arquivos em blocos e guarda os blocos em arquivos .dblock, e o MESMO
  .dblock serve varias datas ao mesmo tempo. Medido neste servidor: cada um
  dos 8 maiores .dblock e usado pelas 2 versoes existentes. Se um dia houver
  30 versoes, o mesmo arquivo servira as 30. Mover, renomear ou separar esses
  arquivos por data destroi todas as versoes de uma vez - inclusive as
  antigas, que e justamente o que o backup existe para proteger.

  O que da para fazer, e o que este script faz, e deixar a NUVEM legivel: as
  pastas por data existem, sao criadas sozinhas e dizem o que aconteceu.

  COMO INSTALAR

      .\pastas-na-nuvem.ps1 -Instalar

  Isso liga o script em todos os backups deste Duplicati. Depois disso ele
  roda sozinho ao fim de cada execucao.

  Para testar sem esperar o backup da noite:

      .\pastas-na-nuvem.ps1 -Simular

================================================================================
#>

[CmdletBinding()]
param(
    # Liga o script nos backups deste Duplicati (roda uma vez, com o Duplicati no ar)
    [switch]$Instalar,

    # Mostra o que seria enviado, sem enviar nada
    [switch]$Simular,

    # Porta do Duplicati, se nao for a padrao
    [int]$PortaDuplicati = 8200
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# --- aparencia ----------------------------------------------------------------

function Titulo($t) { Write-Host ""; Write-Host "  $t" -ForegroundColor Cyan }
function Ok($t)     { Write-Host "    $t" -ForegroundColor Green }
function Aviso($t)  { Write-Host "    $t" -ForegroundColor Yellow }
function Erro($t)   { Write-Host "    $t" -ForegroundColor Red }
function Nota($t)   { Write-Host "    $t" -ForegroundColor DarkGray }

# --- onde esta o Duplicati ----------------------------------------------------

function AcharDuplicati {
    $candidatos = @(
        'C:\Program Files\Duplicati 2',
        'C:\Program Files (x86)\Duplicati 2',
        "$env:LOCALAPPDATA\Programs\Duplicati 2"
    )
    foreach ($c in $candidatos) {
        if (Test-Path (Join-Path $c 'Duplicati.CommandLine.BackendTool.exe')) { return $c }
    }
    throw "nao encontrei a instalacao do Duplicati (procurei em: $($candidatos -join ', '))"
}

# --- formatacao ---------------------------------------------------------------

function Bytes([double]$v) {
    if ($v -le 0) { return '-' }
    $u = @('B', 'KB', 'MB', 'GB', 'TB', 'PB')
    $i = [Math]::Min([Math]::Floor([Math]::Log($v, 1024)), $u.Length - 1)
    $n = $v / [Math]::Pow(1024, $i)
    $casas = if ($n -lt 10 -and $i -gt 0) { 2 } elseif ($n -lt 100 -and $i -gt 0) { 1 } else { 0 }
    return ('{0:N' + $casas + '} {1}') -f $n, $u[$i]
}

function Duracao([string]$txt) {
    # o Duplicati grava a duracao como texto "00:17:43.1234567"
    if (-not $txt) { return '-' }
    $p = $txt.Split(':')
    if ($p.Count -ne 3) { return $txt }
    $h = [int][double]$p[0]; $m = [int][double]$p[1]; $s = [int][double]$p[2]
    if ($h -gt 0) { return ('{0} h {1:00} min' -f $h, $m) }
    if ($m -gt 0) { return ('{0} min {1:00} s' -f $m, $s) }
    return "$s s"
}

function Velocidade([double]$bytes, [string]$duracaoTexto) {
    if ($bytes -le 0 -or -not $duracaoTexto) { return '-' }
    $p = $duracaoTexto.Split(':')
    if ($p.Count -ne 3) { return '-' }
    $seg = [double]$p[0] * 3600 + [double]$p[1] * 60 + [double]$p[2]
    if ($seg -le 0) { return '-' }
    # rede se mede em bits, arquivo em bytes: dai o x8
    $bps = ($bytes * 8) / $seg
    $u = @('bps', 'Kbps', 'Mbps', 'Gbps')
    $i = [Math]::Min([Math]::Floor([Math]::Log($bps, 1000)), $u.Length - 1)
    return ('{0:N1} {1}' -f ($bps / [Math]::Pow(1000, $i)), $u[$i])
}

# --- monta o endereco das pastas de verificacao -------------------------------

<#
    Recebe a URL do backup e devolve a URL de um prefixo IRMAO, no mesmo
    bucket. Exemplo:

        s3://meu-bucket/cartorio-x?...        ->  s3://meu-bucket/cartorio-x-VERIFICACAO/<pasta>?...
        s3://meu-bucket/?...                  ->  s3://meu-bucket/VERIFICACAO/<pasta>?...

    A parte depois de "?" carrega as credenciais e as opcoes; ela e preservada
    inteira e nunca e impressa.
#>
function UrlDaPasta([string]$urlBackup, [string]$pasta) {
    $qs = ''
    $semQs = $urlBackup
    $i = $urlBackup.IndexOf('?')
    if ($i -ge 0) { $semQs = $urlBackup.Substring(0, $i); $qs = $urlBackup.Substring($i) }

    $semQs = $semQs.TrimEnd('/')
    return "$semQs-VERIFICACAO/$pasta$qs"
}

function Mascarar([string]$url) {
    # nunca imprimir credencial: corta tudo a partir do "?" e a senha do userinfo
    $u = $url
    $i = $u.IndexOf('?')
    if ($i -ge 0) { $u = $u.Substring(0, $i) + '?<credenciais ocultas>' }
    return ($u -replace '//[^/@]*@', '//<oculto>@')
}

# --- envia um arquivo pelo backend do proprio Duplicati -----------------------

function EnviarArquivo([string]$pastaDuplicati, [string]$url, [string]$arquivo) {
    $exe = Join-Path $pastaDuplicati 'Duplicati.CommandLine.BackendTool.exe'

    # CREATEFOLDER primeiro: no S3 a "pasta" so aparece no console se existir
    # o objeto com barra no fim. Se o backend nao suportar, segue assim mesmo -
    # o PUT cria o caminho de qualquer jeito.
    & $exe CREATEFOLDER $url 2>&1 | Out-Null

    $saida = & $exe PUT $url $arquivo 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "falha ao enviar $([IO.Path]::GetFileName($arquivo)): $saida"
    }
}

# ==============================================================================
#  MODO 1 - execucao normal, chamado pelo Duplicati depois de cada backup
# ==============================================================================

function Executar {
    $urlBackup = $env:DUPLICATI__REMOTEURL
    $nomeBackup = $env:DUPLICATI__backup_name
    $operacao = $env:DUPLICATI__OPERATIONNAME
    $resultado = $env:DUPLICATI__PARSED_RESULT
    $arquivoResultado = $env:DUPLICATI__RESULTFILE

    if (-not $urlBackup) {
        Erro "sem DUPLICATI__REMOTEURL - este script e chamado pelo Duplicati,"
        Erro "nao pela mao. Use -Instalar para liga-lo, ou -Simular para testar."
        return 1
    }

    # so backup interessa; verificacao, teste e restauracao nao criam versao
    if ($operacao -and $operacao -ne 'Backup') { return 0 }

    $pastaDuplicati = AcharDuplicati

    # --- le o relatorio da execucao -------------------------------------------
    $r = $null
    if ($arquivoResultado -and (Test-Path $arquivoResultado)) {
        try {
            $txt = [System.IO.File]::ReadAllText($arquivoResultado, [System.Text.UTF8Encoding]::new($false))
            $r = $txt | ConvertFrom-Json
        } catch {
            # relatorio ilegivel nao pode impedir o resumo de existir
            $r = $null
        }
    }

    $bs = if ($r) { $r.BackendStatistics } else { $null }
    $enviado = if ($bs) { [double]$bs.BytesUploaded } else { 0 }
    $naNuvem = if ($bs) { [double]$bs.KnownFileSize } else { 0 }
    $origem = if ($r) { [double]$r.SizeOfExaminedFiles } else { 0 }
    $arquivos = if ($r) { [double]$r.ExaminedFiles } else { 0 }
    $duracao = if ($r) { [string]$r.Duration } else { '' }
    $fim = if ($r -and $r.EndTime) { [datetime]$r.EndTime } else { Get-Date }

    # --- FULL ou INCREMENTAL --------------------------------------------------
    #
    # A primeira execucao que chega aqui cria a pasta BACKUP-FULL. Da segunda em
    # diante, uma pasta por data. Nao e o Duplicati que decide isso - para ele
    # toda versao e restauravel por inteiro; e uma leitura para quem abre a AWS.
    $urlRaiz = UrlDaPasta $urlBackup ''
    $temFull = $false
    try {
        $exe = Join-Path $pastaDuplicati 'Duplicati.CommandLine.BackendTool.exe'
        $lista = & $exe LIST $urlRaiz 2>&1
        $temFull = ($LASTEXITCODE -eq 0) -and ($lista -match 'BACKUP-FULL')
    } catch { $temFull = $false }

    $pasta = if ($temFull) { 'BACKUP-INCREMENTAL-' + $fim.ToString('dd-MM-yyyy') }
             else          { 'BACKUP-FULL' }

    # --- escreve o resumo -----------------------------------------------------
    $situacao = switch ("$resultado".ToLower()) {
        'success' { 'BACKUP FEITO COM EXITO' }
        'warning' { 'BACKUP CONCLUIDO COM AVISOS' }
        'error'   { 'BACKUP FALHOU' }
        'fatal'   { 'BACKUP FALHOU' }
        default   { "RESULTADO: $resultado" }
    }

    $linhas = @(
        '=============================================================='
        "  $situacao"
        '=============================================================='
        ''
        "  Cartorio / backup : $nomeBackup"
        "  Data e hora       : $($fim.ToString('dd/MM/yyyy HH:mm:ss'))"
        "  Tipo              : $(if ($pasta -eq 'BACKUP-FULL') { 'Primeira carga (completa)' } else { 'Incremental do dia' })"
        ''
        '  --------------------------------------------------------------'
        "  Enviado nesta execucao : $(Bytes $enviado)"
        "  Velocidade media       : $(Velocidade $enviado $duracao)"
        "  Duracao                : $(Duracao $duracao)"
        ''
        "  Total guardado na nuvem: $(if ($naNuvem -gt 0) { Bytes $naNuvem } else { '- (nao medido nesta execucao)' })"
        "  Tamanho na origem      : $(Bytes $origem)"
        "  Arquivos examinados    : $('{0:N0}' -f $arquivos)"
        '  --------------------------------------------------------------'
        ''
    )

    if ($r -and $r.Errors -and $r.Errors.Count -gt 0) {
        $linhas += '  ERROS:'
        foreach ($e in ($r.Errors | Select-Object -First 8)) { $linhas += "    - $e" }
        $linhas += ''
    }
    if ($r -and $r.Warnings -and $r.Warnings.Count -gt 0) {
        $linhas += '  AVISOS:'
        foreach ($w in ($r.Warnings | Select-Object -First 8)) { $linhas += "    - $w" }
        $linhas += ''
    }

    $linhas += @(
        '  --------------------------------------------------------------'
        '  Esta pasta e so para conferencia. Os arquivos do backup ficam'
        '  na pasta ao lado, com nomes proprios do programa, e NAO devem'
        '  ser movidos, renomeados nem apagados: um mesmo arquivo guarda'
        '  pedaco de varias datas ao mesmo tempo. Mexer neles quebra todas'
        '  as versoes de uma vez.'
        ''
        '  Para restaurar, use o CH.Com Backup na maquina.'
        '  --------------------------------------------------------------'
        "  Gerado automaticamente em $((Get-Date).ToString('dd/MM/yyyy HH:mm:ss'))"
        '  CH.Com Solucoes em Tecnologia'
        ''
    )

    $temp = Join-Path $env:TEMP 'RESUMO.txt'
    # BOM: o Bloco de Notas do Windows so acerta os acentos com ele
    [System.IO.File]::WriteAllText($temp, ($linhas -join "`r`n"), [System.Text.UTF8Encoding]::new($true))

    $urlDestino = UrlDaPasta $urlBackup $pasta

    if ($Simular) {
        Titulo "SIMULACAO - nada foi enviado"
        Nota "destino: $(Mascarar $urlDestino)"
        Write-Host ""
        Get-Content $temp | ForEach-Object { Write-Host "    $_" }
        return 0
    }

    try {
        EnviarArquivo $pastaDuplicati $urlDestino $temp
        Ok "resumo publicado em $pasta"
    } catch {
        # Nunca derrubar o backup por causa disto. O backup e o que importa;
        # o resumo e conveniencia.
        Aviso "nao consegui publicar o resumo: $($_.Exception.Message)"
    } finally {
        Remove-Item $temp -Force -ErrorAction SilentlyContinue
    }

    return 0
}

# ==============================================================================
#  MODO 2 - instalar: liga o script em todos os backups deste Duplicati
# ==============================================================================

function PedirSenha([string]$titulo) {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $f = New-Object System.Windows.Forms.Form
    $f.Text = $titulo; $f.Size = New-Object System.Drawing.Size(430, 170)
    $f.StartPosition = 'CenterScreen'; $f.TopMost = $true
    $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false

    $l = New-Object System.Windows.Forms.Label
    $l.Text = 'Senha do CH.Com Backup (a mesma da tela no navegador):'
    $l.Location = New-Object System.Drawing.Point(14, 15)
    $l.Size = New-Object System.Drawing.Size(390, 20)
    $f.Controls.Add($l)

    $t = New-Object System.Windows.Forms.TextBox
    $t.UseSystemPasswordChar = $true
    $t.Location = New-Object System.Drawing.Point(14, 40)
    $t.Size = New-Object System.Drawing.Size(390, 24)
    $f.Controls.Add($t)

    $b = New-Object System.Windows.Forms.Button
    $b.Text = 'OK'; $b.Location = New-Object System.Drawing.Point(230, 80)
    $b.Size = New-Object System.Drawing.Size(80, 28)
    $b.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $f.Controls.Add($b); $f.AcceptButton = $b

    $c = New-Object System.Windows.Forms.Button
    $c.Text = 'Cancelar'; $c.Location = New-Object System.Drawing.Point(318, 80)
    $c.Size = New-Object System.Drawing.Size(86, 28)
    $c.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $f.Controls.Add($c); $f.CancelButton = $c

    $f.Add_Shown({ $t.Focus() })
    if ($f.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
    return $t.Text
}

function Instalar {
    Titulo "Ligando as pastas de verificacao"

    $meuCaminho = $PSCommandPath
    if (-not $meuCaminho) { $meuCaminho = $MyInvocation.MyCommand.Path }

    # o script fica junto do Duplicati para nao depender da pasta de instalacao
    $pastaDuplicati = AcharDuplicati
    $destino = Join-Path $pastaDuplicati 'chcom-pastas-na-nuvem.ps1'
    Copy-Item $meuCaminho $destino -Force
    Ok "script instalado em $destino"

    $comando = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$destino`""

    $base = "http://127.0.0.1:$PortaDuplicati"
    $senha = PedirSenha 'CH.Com Backup'
    if (-not $senha) { Aviso "cancelado - nada foi alterado."; return }

    try {
        $login = Invoke-RestMethod "$base/api/v1/auth/login" -Method Post -TimeoutSec 20 `
            -ContentType 'application/json' `
            -Body (@{ Password = $senha; RememberMe = $false } | ConvertTo-Json)
    } catch {
        Erro "senha recusada pelo CH.Com Backup. Nada foi alterado."
        return
    } finally {
        # nao deixar a senha viva na sessao
        $senha = $null
        [GC]::Collect()
    }

    $cab = @{ Authorization = "Bearer $($login.AccessToken)" }

    # opcao no nivel do servidor: vale para todos os backups
    $corpo = @{
        '--run-script-after'                = $comando
        '--run-script-result-output-format' = 'Json'
        '--run-script-timeout'              = '10m'
    } | ConvertTo-Json

    Invoke-RestMethod "$base/api/v1/serversettings" -Method Patch -Headers $cab `
        -ContentType 'application/json' -Body $corpo -TimeoutSec 20 | Out-Null
    Ok "ligado na configuracao do servidor"

    # backups que tem opcao propria sobrescrevem a do servidor: tratar um a um
    $ajustados = 0
    $lista = Invoke-RestMethod "$base/api/v1/backups" -Headers $cab -TimeoutSec 20
    foreach ($item in $lista) {
        $bid = $item.Backup.ID
        if (-not $bid) { continue }
        $det = Invoke-RestMethod "$base/api/v1/backup/$bid" -Headers $cab -TimeoutSec 20
        $cfgb = if ($det.data) { $det.data } else { $det }
        $sets = $cfgb.Backup.Settings
        if (-not $sets) { continue }

        $propria = $sets | Where-Object { $_.Name -eq '--run-script-after' }
        if (-not $propria) { continue }

        $propria.Value = $comando
        Invoke-RestMethod "$base/api/v1/backup/$bid" -Method Put -Headers $cab `
            -ContentType 'application/json' -Body ($cfgb | ConvertTo-Json -Depth 12) -TimeoutSec 30 | Out-Null
        $ajustados++
    }
    if ($ajustados -gt 0) { Ok "$ajustados backup(s) com opcao propria tambem ajustado(s)" }

    Write-Host ""
    Ok "PRONTO."
    Nota "Na proxima execucao de cada backup, as pastas comecam a aparecer na AWS."
    Nota "A primeira cria BACKUP-FULL; as seguintes, BACKUP-INCREMENTAL-DD-MM-AAAA."
}

# ==============================================================================

if ($Instalar) {
    try { Instalar } catch { Erro $_.Exception.Message; exit 1 }
    exit 0
}

exit (Executar)
