<#
================================================================================
  CH.Com Backup - regras padrao do cartorio

  Aplica de uma vez as configuracoes que todo cartorio deve ter. Serve para
  deixar o backup subindo direito para a AWS ANTES de o painel existir - o
  envio de relatorio e opcional e pode ser ligado depois, sem refazer nada.

  O QUE ELE LIGA, E POR QUE

  --snapshot-policy=auto
      Usa a Copia de Sombra do Windows (VSS). E o que faz o backup conseguir
      ler arquivo aberto por outro programa - tipicamente o banco de dados do
      sistema do cartorio, que fica aberto o dia inteiro.

      Sem isso o Duplicati avisa "the process cannot access the file" e SEGUE
      SEM COPIAR aquele arquivo. O backup termina verde, e o dado mais
      importante do cartorio nao esta la. Esta e a configuracao mais
      importante deste script.

      "auto" e nao "required": com required, o backup inteiro falha se o VSS
      nao estiver disponivel na maquina. Melhor copiar o que da do que nao
      copiar nada.

  --exclude={SystemFiles,OperatingSystem,TemporaryFiles,CacheFiles}
      Grupos de filtro que o proprio Duplicati mantem. Tiram lixeira,
      pagefile.sys, System Volume Information, C:Windows, pastas Temp e
      cache de navegador - coisas que nao se restaura e que so geram aviso.

      OperatingSystem exclui C:Windows inteiro. Entrou porque os cartorios
      marcam o disco C: todo como origem, e o Windows protege arquivos dele
      mesmo: sem esse grupo o log enche de "Access to the path is denied" em
      LogFilesWMI, em WindowsTemp e em ProtectRecovery - avisos que nao
      significam nada e escondem os que significam. Nao se perde nada: numa
      reinstalacao o Windows e instalado do zero, nao restaurado do backup.

      NAO inclui o grupo Applications de proposito: ele exclui
      C:Program Files inteiro, e varios sistemas de cartorio guardam o banco
      de dados dentro da pasta do proprio programa. Excluir isso nao gera
      erro nenhum - so deixa de copiar, em silencio.

  --number-of-retries=10 e --retry-delay=30s
      O padrao e 5 tentativas com 10 segundos. Link de cartorio do interior
      oscila, e uma queda de meio minuto no meio da madrugada nao pode
      derrubar o backup inteiro.

  O QUE ELE NAO MEXE

  Retencao (quantas versoes guardar) so muda com -Retencao, e com aviso:
  definir uma politica onde nao havia faz o Duplicati APAGAR versoes antigas
  na proxima execucao. Isso e destrutivo e nao pode acontecer de surpresa.

  USO

      .\aplicar-regras.ps1 -Simular      mostra o que mudaria, sem mudar
      .\aplicar-regras.ps1               aplica
      .\aplicar-regras.ps1 -UrlPainel https://painel.exemplo.com.br -Token abc
                                         aplica e liga o envio ao painel

================================================================================
#>

[CmdletBinding()]
param(
    [switch]$Simular,
    [int]$PortaDuplicati = 8200,

    # Painel: opcional. Sem isto o backup roda igual, so nao reporta.
    [string]$UrlPainel,
    [string]$Token,

    # Limite de banda, em KB/s. 0 = sem limite.
    [int]$LimiteUploadKB = 0,

    # Retencao: DESTRUTIVO. Ver o cabecalho.
    [switch]$Retencao,
    [string]$PoliticaRetencao = '7D:0s,4W:1D,12M:1W',

    <#
        Manda tudo para o S3 Glacier Deep Archive.

        So faz sentido quando a janela de recuperacao aceita ESPERAR o
        descongelamento - 12 h no resgate padrao, ate 48 h no resgate em lote.
        Para "apagaram um contrato agora de manha" isto nao serve.

        Liga junto, obrigatoriamente, mais duas coisas. Nao sao preferencia:

          --no-auto-compact
              A compactacao LE arquivos .dblock antigos para reempacotar. No
              Deep Archive eles estao congelados, e a operacao falharia toda
              vez. Sem desligar, o backup passa a acusar erro todo mes.

          --backup-test-samples = 0
              Depois de cada backup o Duplicati BAIXA uma amostra para
              conferir. Em Deep Archive isso falha - e, se conseguisse,
              custaria resgate todo dia.

        Com essas duas desligadas, some a conferencia automatica do backup.
        E o preco de guardar barato, e precisa ser sabido: a checagem passa a
        ser sua, num teste de restauracao de vez em quando.
    #>
    [switch]$ArquivoMorto
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Titulo($t) { Write-Host ""; Write-Host "  $t" -ForegroundColor Cyan }
function Ok($t)     { Write-Host "    $t" -ForegroundColor Green }
function Aviso($t)  { Write-Host "    $t" -ForegroundColor Yellow }
function Erro($t)   { Write-Host "    $t" -ForegroundColor Red }
function Nota($t)   { Write-Host "    $t" -ForegroundColor DarkGray }

# --- as regras ---------------------------------------------------------------

$REGRAS = [ordered]@{
    '--snapshot-policy'   = 'auto'
    '--exclude'           = '{SystemFiles,OperatingSystem,TemporaryFiles,CacheFiles}'
    '--number-of-retries' = '10'
    '--retry-delay'       = '30s'
}

if ($LimiteUploadKB -gt 0) { $REGRAS['--throttle-upload'] = "${LimiteUploadKB}KB" }
if ($Retencao) { $REGRAS['--retention-policy'] = $PoliticaRetencao }

<#
    A CLASSE DE ARMAZENAMENTO NAO E GRAVADA NO DUPLICATI.

    Quem manda os dados para o Glacier Deep Archive e uma regra de ciclo de
    vida no proprio bucket da AWS - ver AWS-REGRA-DEEP-ARCHIVE.txt.

    Duas razoes para preferir la:

      1. A regra da AWS pega o que JA SUBIU. A opcao do Duplicati so vale
         para arquivo novo, e o que ja estava em Standard ficaria em
         Standard para sempre, vinte vezes mais caro.

      2. Com a classe valendo no Duplicati, o teste de conexao do destino
         falha: ele grava um arquivo de prova, que ja nasce congelado, e
         nao consegue le-lo de volta. O tecnico ve "Falha na conexao de
         teste" numa configuracao correta e desfaz o que estava certo.

    Custo de fazer pela AWS: cada arquivo passa um dia em Standard antes de
    ser movido. Em 15 TB isso da centavos.

    Se a opcao estiver gravada de execucoes anteriores, este script REMOVE.
#>
$REGRAS_DO_BACKUP = [ordered]@{}

# Opcoes que o Duplicati NAO pode mais gravar: a classe vem da regra da AWS.
$REGRAS_A_REMOVER = @()

if ($ArquivoMorto) {
    $REGRAS_A_REMOVER = @("--s3-storage-class", "s3-storage-class")

    # Estas duas continuam necessarias: depois de um dia os arquivos estao
    # congelados, e tanto a compactacao quanto a conferencia precisam LER.
    $REGRAS['--no-auto-compact']     = 'true'
    $REGRAS['--backup-test-samples'] = '0'
}

<#
    Filtros que os grupos NAO cobrem, e que precisam ser gravados no backup.

    O grupo SystemFiles exclui "?:\$Recycle.Bin\" - ancorado na RAIZ do disco.
    A lixeira que aparece dentro de uma pasta compartilhada, como

        Z:\...\DADOS_CARTORIO\TERMINAL-03\Desktop\$RECYCLE.BIN\

    passa direto por ele. Isso foi medido com o test-filters do proprio
    Duplicati, nao suposto - e e justamente o caso que aparecia nos avisos.

    Arquivo apagado por um funcionario nao precisa ir para a nuvem todo dia.
#>
$FILTROS_EXTRA = @(
    '*\$RECYCLE.BIN\'
)

# --- senha, sem passar por linha de comando ----------------------------------

function PedirSenha {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $f = New-Object Windows.Forms.Form
    $f.Text = 'CH.Com Backup'
    $f.Size = New-Object Drawing.Size(440, 175)
    $f.StartPosition = 'CenterScreen'; $f.TopMost = $true
    $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false

    $l = New-Object Windows.Forms.Label
    $l.Text = 'Senha de acesso ao CH.Com Backup deste servidor:'
    $l.Location = New-Object Drawing.Point(14, 16)
    $l.Size = New-Object Drawing.Size(400, 20)
    $f.Controls.Add($l)

    $t = New-Object Windows.Forms.TextBox
    $t.UseSystemPasswordChar = $true
    $t.Location = New-Object Drawing.Point(14, 44)
    $t.Size = New-Object Drawing.Size(400, 24)
    $f.Controls.Add($t)

    $ok = New-Object Windows.Forms.Button
    $ok.Text = 'OK'; $ok.Location = New-Object Drawing.Point(240, 84)
    $ok.Size = New-Object Drawing.Size(80, 28); $ok.DialogResult = 'OK'
    $f.Controls.Add($ok); $f.AcceptButton = $ok

    $c = New-Object Windows.Forms.Button
    $c.Text = 'Cancelar'; $c.Location = New-Object Drawing.Point(328, 84)
    $c.Size = New-Object Drawing.Size(86, 28); $c.DialogResult = 'Cancel'
    $f.Controls.Add($c); $f.CancelButton = $c

    $f.Add_Shown({ $t.Focus() })
    if ($f.ShowDialog() -ne 'OK') { return $null }
    return $t.Text
}

# ==============================================================================

Titulo 'Regras padrao do CH.Com Backup'

# O icone da bandeja sobe o servidor com a lista
# 8200,8300,8400,8500,8600,8700,8800,8900,8989 e fica com a primeira livre.
# Gravar as regras no programa errado - ou nao achar programa nenhum porque
# ele escorregou para a 8300 - sao os dois modos de errar aqui.
$PORTAS_POSSIVEIS = @(8200, 8300, 8400, 8500, 8600, 8700, 8800, 8900, 8989)

function NoAr([int]$p) {
    try { $c = New-Object Net.Sockets.TcpClient; $c.Connect('127.0.0.1', $p); $c.Close(); return $true }
    catch { return $false }
}

$portasVivas = @($PORTAS_POSSIVEIS | Where-Object { NoAr $_ })

if ($portasVivas.Count -eq 0) {
    Erro 'o CH.Com Backup nao esta respondendo neste servidor.'
    Nota 'Abra o atalho na area de trabalho e rode isto de novo.'
    exit 1
}

# Se a porta normal responde, e nela que se fala. Senao, na que houver.
if ($portasVivas -notcontains $PortaDuplicati) {
    $PortaDuplicati = $portasVivas[0]
    Aviso "o programa esta na porta $PortaDuplicati, e nao na 8200."
}

if ($portasVivas.Count -gt 1) {
    Write-Host ''
    Erro "HA $($portasVivas.Count) PROGRAMAS RODANDO NESTE SERVIDOR."
    Nota  "portas respondendo: $($portasVivas -join ', ')"
    Nota  'Gravar as regras em um deles nao conserta o outro, e os dois fazem'
    Nota  'o mesmo backup ao mesmo tempo - que e um problema maior que as regras.'
    Nota  'Reinicie este servidor primeiro. Depois rode o DIAGNOSTICO.bat e'
    Nota  'confira que sobrou so a 8200. So entao rode este script.'
    exit 1
}

$base = "http://127.0.0.1:$PortaDuplicati"
Ok "programa no ar na porta $PortaDuplicati"

Write-Host ''
Nota 'Vai aplicar na configuracao do servidor:'
foreach ($k in $REGRAS.Keys) { Nota ("  {0,-22} {1}" -f $k, $REGRAS[$k]) }
if ($REGRAS_A_REMOVER.Count -gt 0) {
    Write-Host ''
    Nota 'E vai REMOVER (a classe vem da regra da AWS, nao daqui):'
    foreach ($k in ($REGRAS_A_REMOVER | Select-Object -Unique)) { Nota ("  {0}" -f $k) }
}
Write-Host ''
foreach ($f in $FILTROS_EXTRA) { Nota ("  {0,-22} {1}" -f 'filtro extra', $f) }
if ($UrlPainel -and $Token) {
    Nota ("  {0,-22} {1}/api/report/<token>" -f '--send-http-json-urls', $UrlPainel.TrimEnd('/'))
}
if ($Retencao) {
    Write-Host ''
    Aviso 'RETENCAO LIGADA: na proxima execucao o Duplicati vai APAGAR versoes'
    Aviso 'antigas que nao couberem na politica. Isso nao tem volta.'
}

if ($ArquivoMorto) {
    Write-Host ''
    Aviso 'ARQUIVO MORTO (Deep Archive):'
    Aviso '  - restaurar exige descongelar antes: 12 h no resgate padrao.'
    Aviso '  - a conferencia automatica do backup fica DESLIGADA.'
    Aviso '  - arquivo apagado antes de 180 dias e cobrado como 180.'
    Nota  '  O procedimento de restauracao esta em RESTAURAR-DO-ARQUIVO-MORTO.txt.'
    Nota  '  A classe de armazenamento vem da regra de ciclo de vida do'
    Nota  '  bucket, nao daqui - ver AWS-REGRA-DEEP-ARCHIVE.txt.'
    Nota  '  Por isso o teste de conexao do destino funciona normalmente.'
}

if ($Simular) {
    Write-Host ''
    Titulo 'SIMULACAO - nada foi alterado'
    exit 0
}

<#
    Entra no programa. Ate tres tentativas, e diz o que REALMENTE aconteceu.

    Isto era um try/catch que respondia "senha recusada" para qualquer falha,
    e abortava na primeira. Duas coisas erradas nisso:

    - Um erro de digitacao custava rodar o .bat de novo, do zero.
    - Quando o problema NAO era a senha - versao antiga sem essa rota, o
      programa caindo no meio, a porta ocupada por outra coisa - a mensagem
      mandava o tecnico atras da senha, que estava certa o tempo todo.

    Agora o codigo HTTP decide: 401 e 403 sao senha; o resto nao e, e o
    script fala o que e.
#>
function EntrarNoPrograma([string]$endereco) {
    for ($tentativa = 1; $tentativa -le 3; $tentativa++) {
        $senha = PedirSenha
        if (-not $senha) { Aviso 'cancelado - nada foi alterado.'; return $null }

        try {
            return Invoke-RestMethod "$endereco/api/v1/auth/login" -Method Post -TimeoutSec 20 `
                -ContentType 'application/json' `
                -Body (@{ Password = $senha; RememberMe = $false } | ConvertTo-Json)
        } catch {
            $codigo = 0
            if ($_.Exception.Response) { $codigo = [int]$_.Exception.Response.StatusCode }

            if ($codigo -eq 401 -or $codigo -eq 403) {
                if ($tentativa -lt 3) {
                    Aviso "senha recusada - tentativa $tentativa de 3."
                    continue
                }
                Erro 'senha recusada tres vezes. Nada foi alterado.'
                Nota 'E a senha do CH.Com Backup DESTE servidor - a mesma de abrir'
                Nota "  $endereco  no navegador daqui."
                Nota 'Nao e a senha do Painel, nem a da AWS, nem a do Windows.'
                Nota 'Esqueceu? O DEFINIR-SENHA.bat troca sem precisar saber a atual.'
                return $null
            }

            if ($codigo -eq 404) {
                Erro 'este servidor tem uma versao do programa sem essa rota de acesso.'
                Nota 'Rode o DIAGNOSTICO.bat para ver a versao instalada.'
                return $null
            }

            Erro 'nao consegui entrar no programa. Nada foi alterado.'
            if ($codigo -gt 0) { Nota "resposta do servidor: $codigo" }
            Nota $_.Exception.Message
            return $null
        } finally {
            $senha = $null
            [GC]::Collect()
        }
    }
}

$login = EntrarNoPrograma $base
if (-not $login) { exit 1 }
$cab = @{ Authorization = "Bearer $($login.AccessToken)" }

<#
    Limpa opcoes com nome quebrado antes de qualquer coisa.

    O Duplicati guarda o nome da opcao COM os dois tracos e tira dois na hora
    de rodar. Quem digita "--exclude" no campo "Adicionar opcao avancada" -
    que ja poe os tracos sozinho - acaba gravando "----exclude". Ao rodar,
    sobra "--exclude", que nao e opcao nenhuma, e o Duplicati avisa:

        A opcao fornecida ----exclude nao e suportada e ira ser ignorada

    O aviso passa no meio de dezenas de linhas de log e ninguem ve. O efeito
    e que a regra simplesmente NAO VALE: sem filtro, sem VSS, e o backup
    continua rodando e dizendo que deu certo.

    Foi exatamente o que aconteceu no primeiro cartorio.
#>
function LimparOpcoesQuebradas($lista) {
    $ruins = @($lista | Where-Object { $_.Name -match '^-{3,}' })
    foreach ($r in $ruins) { Aviso "removendo opcao invalida: $($r.Name)" }
    return @($lista | Where-Object { $_.Name -notmatch '^-{3,}' })
}

# --- 1. opcoes do servidor: valem para todos os backups da maquina -----------
Titulo 'Gravando as regras'

# Apaga primeiro o que estiver com o nome quebrado. Mandar valor nulo no
# PATCH e o que remove a opcao do servidor.
$atuais = Invoke-RestMethod "$base/api/v1/serversettings" -Headers $cab -TimeoutSec 20
$quebradas = @($atuais.PSObject.Properties | Where-Object { $_.Name -match "^-{3,}" -or $REGRAS_A_REMOVER -contains $_.Name })
if ($quebradas.Count -gt 0) {
    $limpar = @{}
    foreach ($d in $quebradas) {
        Aviso "removendo opcao invalida do servidor: $($d.Name)"
        $limpar[$d.Name] = $null
    }
    Invoke-RestMethod "$base/api/v1/serversettings" -Method Patch -Headers $cab `
        -ContentType "application/json" -Body ($limpar | ConvertTo-Json) -TimeoutSec 20 | Out-Null
}

$corpo = @{}
foreach ($k in $REGRAS.Keys) { $corpo[$k] = $REGRAS[$k] }
Invoke-RestMethod "$base/api/v1/serversettings" -Method Patch -Headers $cab `
    -ContentType 'application/json' -Body ($corpo | ConvertTo-Json) -TimeoutSec 20 | Out-Null
Ok 'regras gravadas na configuracao do servidor'

# --- 2. backups com opcao propria --------------------------------------------
#
# A opcao definida em UM backup ignora a do servidor - nao soma. Um cartorio
# que ja tinha, por exemplo, --exclude proprio continuaria sem os filtros
# novos, e ninguem perceberia porque nenhum erro aparece.
$ajustados = 0
$lista = Invoke-RestMethod "$base/api/v1/backups" -Headers $cab -TimeoutSec 20
foreach ($item in $lista) {
    $bid = $item.Backup.ID
    if (-not $bid) { continue }

    $det = Invoke-RestMethod "$base/api/v1/backup/$bid" -Headers $cab -TimeoutSec 20
    $cfg = if ($det.data) { $det.data } else { $det }
    $sets = $cfg.Backup.Settings
    if (-not $sets) { continue }

    $mudou = $false

    $antes = @($sets).Count
    $sets = LimparOpcoesQuebradas $sets
    if (@($sets).Count -ne $antes) { $cfg.Backup.Settings = $sets; $mudou = $true }

    # 2a. opcao propria conflitando com a do servidor: alinhar
    foreach ($k in $REGRAS.Keys) {
        $propria = $sets | Where-Object { $_.Name -eq $k -or $_.Name -eq $k.TrimStart('-') }
        if ($propria -and $propria.Value -ne $REGRAS[$k]) {
            Nota "$($cfg.Backup.Name): $k proprio ('$($propria.Value)') -> '$($REGRAS[$k])'"
            $propria.Value = $REGRAS[$k]
            $mudou = $true
        }
    }

    # 2b. tirar as opcoes que nao devem mais existir aqui
    foreach ($k in $REGRAS_A_REMOVER) {
        $achada = @($sets | Where-Object { $_.Name -eq $k })
        if ($achada.Count -gt 0) {
            Aviso "$($cfg.Backup.Name): removendo $k (agora vem da regra da AWS)"
            $sets = @($sets | Where-Object { $_.Name -ne $k })
            $cfg.Backup.Settings = $sets
            $mudou = $true
        }
    }

    # --- filtros que os grupos nao cobrem ------------------------------------
    #
    # Vao na lista de filtros do backup, nao como opcao: a opcao --exclude
    # guarda um valor so, e ele ja esta ocupado pelos grupos.
    $filtros = @()
    if ($cfg.Backup.Filters) { $filtros = @($cfg.Backup.Filters) }

    foreach ($expr in $FILTROS_EXTRA) {
        $ja = $filtros | Where-Object { $_.Expression -eq $expr }
        if ($ja) { continue }

        $ordem = 0
        if ($filtros.Count -gt 0) {
            $ordem = (($filtros | ForEach-Object { [int]$_.Order } | Measure-Object -Maximum).Maximum) + 1
        }
        $filtros += [PSCustomObject]@{ Order = $ordem; Include = $false; Expression = $expr }
        Nota "$($cfg.Backup.Name): filtro acrescentado -> $expr"
        $mudou = $true
    }
    $cfg.Backup.Filters = $filtros

    if ($mudou) {
        Invoke-RestMethod "$base/api/v1/backup/$bid" -Method Put -Headers $cab `
            -ContentType 'application/json' -Body ($cfg | ConvertTo-Json -Depth 12) -TimeoutSec 30 | Out-Null
        $ajustados++
    }
}
if ($ajustados -gt 0) { Ok "$ajustados backup(s) que tinham opcao propria foram alinhados" }
else { Nota 'nenhum backup tinha opcao propria conflitante' }

# --- 3. painel (opcional) -----------------------------------------------------
if ($UrlPainel -and $Token) {
    Titulo 'Ligando o envio ao painel'
    $url = "$($UrlPainel.TrimEnd('/'))/api/report/$Token"

    $cfgServidor = Invoke-RestMethod "$base/api/v1/serversettings" -Headers $cab -TimeoutSec 20
    $atual = $cfgServidor.'--send-http-json-urls'
    $partes = @()
    if ($atual) { $partes = $atual.Split(';') | ForEach-Object { $_.Trim() } | Where-Object { $_ } }

    if ($partes -contains $url) {
        Ok 'ja estava configurado'
    } else {
        # ACRESCENTA, nao substitui: o cartorio pode ja mandar relatorio para
        # outro sistema, e trocar sem avisar quebraria aquilo em silencio.
        $nova = (($partes + $url) -join ';')
        Invoke-RestMethod "$base/api/v1/serversettings" -Method Patch -Headers $cab `
            -ContentType 'application/json' `
            -Body (@{ '--send-http-json-urls' = $nova } | ConvertTo-Json) -TimeoutSec 20 | Out-Null
        Ok 'envio ao painel ligado'
    }
} else {
    Nota 'sem painel configurado - o backup roda igual, so nao reporta'
    Nota 'para ligar depois: .\aplicar-regras.ps1 -UrlPainel <endereco> -Token <token>'
}

# --- conferencia --------------------------------------------------------------
Titulo 'Conferindo'
$final = Invoke-RestMethod "$base/api/v1/serversettings" -Headers $cab -TimeoutSec 20
$faltou = @()
foreach ($k in $REGRAS.Keys) {
    if ($final.$k -ne $REGRAS[$k]) { $faltou += "$k (esperado '$($REGRAS[$k])', esta '$($final.$k)')" }
}
if ($faltou.Count -eq 0) {
    Ok 'todas as regras conferidas no servidor'
} else {
    foreach ($f in $faltou) { Aviso "nao gravou: $f" }
}

Write-Host ''
Write-Host '  ============================================================' -ForegroundColor Green
Write-Host '    CARTORIO CONFIGURADO' -ForegroundColor Green
Write-Host '  ============================================================' -ForegroundColor Green
Write-Host ''
Nota 'O proximo backup ja roda com estas regras.'
Nota 'Dispare um agora pela tela para conferir: http://localhost:8200'
Write-Host ''
