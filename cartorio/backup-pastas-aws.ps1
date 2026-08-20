<#
================================================================================
  CH.Com Backup - copia por pastas datadas na AWS

  O QUE ELE FAZ

  Manda os arquivos do cartorio para a AWS do jeito que se le no console:

      BACKUP-FULL/                        <- a carga inteira, na 1a vez
          C/Dados/Cartorio/livro-1.pdf
          C/Dados/Cartorio/livro-2.pdf
      BACKUP-INCREMENTAL-14-08-2026/      <- so o que mudou naquele dia
          C/Dados/Cartorio/livro-2.pdf
      BACKUP-INCREMENTAL-15-08-2026/
          C/Dados/Cartorio/livro-9.pdf

  Arquivo de verdade, com o nome de verdade, na arvore de pastas de verdade.
  Da para abrir no console da AWS, achar um documento e baixar direto, sem
  programa nenhum no meio.

  Cada pasta ganha um RESUMO.txt e uma LISTA.csv com tudo o que foi enviado.

  COMO ELE DECIDE O QUE MANDAR

  Guarda um indice local (indice-aws.json) com caminho, tamanho e data de
  alteracao de cada arquivo ja enviado. Na execucao seguinte, manda so o que
  e novo ou mudou. Arquivo apagado na origem fica registrado no RESUMO do dia,
  mas NAO e apagado da nuvem - a nuvem so cresce, que e o que se espera de um
  backup.

  O QUE VOCE PERDE EM RELACAO AO DUPLICATI, PARA SABER

  - Sem deduplicacao: se o mesmo arquivo existir em dois lugares, sobe duas
    vezes. Ocupa mais espaco na AWS.
  - Sem criptografia do lado do cliente. O Duplicati embaralha antes de subir;
    aqui o arquivo sobe como ele e. Por isso este script LIGA a criptografia
    do lado da Amazon (SSE-S3, AES256) em todo envio: o dado fica cifrado no
    disco da AWS. Mas quem tiver a credencial le o conteudo, o que com o
    Duplicati nao acontecia. Para dado de cartorio isso importa - a decisao e
    sua, e esta anotada aqui para nao se perder.
  - Sem restauracao automatica: recuperar e baixar o arquivo, na mao.

  O Duplicati continua rodando em paralelo se voce quiser os dois.

  COMO USAR

      .\backup-pastas-aws.ps1 -Configurar     define bucket, regiao, credencial e origem
      .\backup-pastas-aws.ps1 -Testar         envia um arquivo pequeno e le de volta
      .\backup-pastas-aws.ps1 -Simular        mostra o que subiria, sem subir
      .\backup-pastas-aws.ps1                 executa
      .\backup-pastas-aws.ps1 -Instalar       agenda para rodar todo dia

================================================================================
#>

[CmdletBinding()]
param(
    [switch]$Configurar,
    [switch]$Testar,
    [switch]$Simular,
    [switch]$Instalar,

    # hora da execucao diaria quando usar -Instalar
    [string]$Hora = '22:00',

    # --- configuracao sem dialogo -------------------------------------------
    # Em 100 cartorios ninguem clica em seis caixas de dialogo. Com estes
    # parametros o -Configurar roda calado, e da para chamar de um .bat, de
    # um script de implantacao ou do RMM.
    [string]$Bucket,
    [string]$Regiao,
    [string]$Prefixo,
    [string[]]$Origem,
    [string]$ChaveAws,
    [string]$SegredoAws,

    # painel central: os 100 aparecem numa tela so
    [string]$UrlPainel,
    [string]$Token,

    # limite de banda em megabits por segundo (0 = sem limite).
    # Cartorio com link fino nao pode ficar sem internet no horario de servico.
    [double]$LimiteMbps = 0
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$PastaEstado = Join-Path $env:ProgramData 'CH.Com Backup'
$ArquivoConfig = Join-Path $PastaEstado 'config-aws.json'
$ArquivoIndice = Join-Path $PastaEstado 'indice-aws.json'
$ArquivoLog = Join-Path $PastaEstado 'copia-aws.log'

# --- aparencia ----------------------------------------------------------------

function Escrever($t, $cor) {
    Write-Host $t -ForegroundColor $cor
    try {
        $carimbo = (Get-Date).ToString('dd/MM/yyyy HH:mm:ss')
        Add-Content -Path $ArquivoLog -Value "$carimbo  $($t.Trim())" -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch { }
}
function Titulo($t) { Write-Host ""; Escrever "  $t" Cyan }
function Ok($t)     { Escrever "    $t" Green }
function Aviso($t)  { Escrever "    $t" Yellow }
function Erro($t)   { Escrever "    $t" Red }
function Nota($t)   { Escrever "    $t" DarkGray }

function Bytes([double]$v) {
    if ($v -le 0) { return '0 B' }
    $u = @('B', 'KB', 'MB', 'GB', 'TB')
    $i = [Math]::Min([Math]::Floor([Math]::Log($v, 1024)), $u.Length - 1)
    $n = $v / [Math]::Pow(1024, $i)
    $c = if ($n -lt 10 -and $i -gt 0) { 2 } elseif ($n -lt 100 -and $i -gt 0) { 1 } else { 0 }
    return ('{0:N' + $c + '} {1}') -f $n, $u[$i]
}

# ==============================================================================
#  ASSINATURA DA AMAZON (Signature Version 4)
#
#  A AWS nao aceita usuario e senha num cabecalho: cada pedido leva uma
#  assinatura derivada da chave secreta, da data, da regiao e do conteudo do
#  proprio pedido. E isto que substitui o AWS CLI, que nao esta instalado, e o
#  SDK que vem com o Duplicati, que e .NET 8 e nao carrega no PowerShell do
#  Windows.
# ==============================================================================

function HmacSha256([byte[]]$chave, [string]$texto) {
    $h = New-Object System.Security.Cryptography.HMACSHA256
    $h.Key = $chave
    $r = $h.ComputeHash([Text.Encoding]::UTF8.GetBytes($texto))
    $h.Dispose()
    return $r
}

function Sha256Hex([byte[]]$dados) {
    $s = [System.Security.Cryptography.SHA256]::Create()
    $r = $s.ComputeHash($dados)
    $s.Dispose()
    return -join ($r | ForEach-Object { $_.ToString('x2') })
}

function HexDe([byte[]]$b) { return -join ($b | ForEach-Object { $_.ToString('x2') }) }

<#
    Codificacao do caminho conforme a AWS exige: cada segmento e codificado,
    mas a barra continua barra. Nao serve o UrlEncode do .NET, que troca
    espaco por "+" e nao codifica alguns caracteres que a AWS exige.
#>
function CodificarCaminho([string]$caminho) {
    $seguros = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~'
    $sb = New-Object Text.StringBuilder
    foreach ($b in [Text.Encoding]::UTF8.GetBytes($caminho)) {
        $ch = [char]$b
        if ($ch -eq '/') { [void]$sb.Append('/') }
        elseif ($seguros.IndexOf($ch) -ge 0) { [void]$sb.Append($ch) }
        else { [void]$sb.AppendFormat('%{0:X2}', $b) }
    }
    return $sb.ToString()
}

<#
    Monta e dispara um pedido assinado. O corpo pode vir como bytes (envio
    pequeno) ou como caminho de arquivo (envio grande, transmitido em fluxo
    para nao carregar 2 GB na memoria).
#>
function ChamarS3 {
    param(
        [string]$Metodo,
        [string]$Chave,              # caminho do objeto dentro do bucket
        [string]$Consulta = '',      # ex: 'uploads=' ou 'partNumber=1&uploadId=xyz'
        [byte[]]$Corpo = $null,
        [string]$ArquivoCorpo = $null,
        [hashtable]$CabecalhosExtra = $null,
        [switch]$SemAssinarConteudo  # UNSIGNED-PAYLOAD: evita ler o arquivo so para somar
    )

    $cfg = $script:Config
    $host_ = "$($cfg.Bucket).s3.$($cfg.Regiao).amazonaws.com"
    $agora = [DateTime]::UtcNow
    $dataHora = $agora.ToString('yyyyMMddTHHmmssZ')
    $data = $agora.ToString('yyyyMMdd')
    $escopo = "$data/$($cfg.Regiao)/s3/aws4_request"

    if ($SemAssinarConteudo) {
        $hashConteudo = 'UNSIGNED-PAYLOAD'
    } elseif ($Corpo) {
        $hashConteudo = Sha256Hex $Corpo
    } else {
        $hashConteudo = Sha256Hex ([byte[]]@())
    }

    $cab = @{
        'host'                 = $host_
        'x-amz-content-sha256' = $hashConteudo
        'x-amz-date'           = $dataHora
    }
    if ($CabecalhosExtra) { foreach ($k in $CabecalhosExtra.Keys) { $cab[$k.ToLower()] = $CabecalhosExtra[$k] } }

    $nomesOrdenados = $cab.Keys | Sort-Object
    $cabCanonico = ($nomesOrdenados | ForEach-Object { "$_`:$($cab[$_])" }) -join "`n"
    $assinados = ($nomesOrdenados) -join ';'

    $uriCanonico = CodificarCaminho ('/' + $Chave.TrimStart('/'))

    # a consulta canonica precisa vir ordenada por nome do parametro
    $consultaCanonica = ''
    if ($Consulta) {
        $partes = $Consulta.Split('&') | ForEach-Object {
            $kv = $_.Split('=', 2)
            [PSCustomObject]@{ n = $kv[0]; v = if ($kv.Count -gt 1) { $kv[1] } else { '' } }
        }
        $consultaCanonica = (($partes | Sort-Object n) | ForEach-Object {
            (CodificarCaminho $_.n) + '=' + (CodificarCaminho $_.v)
        }) -join '&'
    }

    $pedidoCanonico = @(
        $Metodo, $uriCanonico, $consultaCanonica, ($cabCanonico + "`n"), $assinados, $hashConteudo
    ) -join "`n"

    $paraAssinar = @(
        'AWS4-HMAC-SHA256', $dataHora, $escopo,
        (Sha256Hex ([Text.Encoding]::UTF8.GetBytes($pedidoCanonico)))
    ) -join "`n"

    $k = [Text.Encoding]::UTF8.GetBytes('AWS4' + $cfg.Segredo)
    $k = HmacSha256 $k $data
    $k = HmacSha256 $k $cfg.Regiao
    $k = HmacSha256 $k 's3'
    $k = HmacSha256 $k 'aws4_request'
    $assinatura = HexDe (HmacSha256 $k $paraAssinar)

    $autorizacao = "AWS4-HMAC-SHA256 Credential=$($cfg.Chave)/$escopo, " +
                   "SignedHeaders=$assinados, Signature=$assinatura"

    $url = "https://$host_$uriCanonico"
    if ($consultaCanonica) { $url += "?$consultaCanonica" }

    $req = [Net.HttpWebRequest]::Create($url)
    $req.Method = $Metodo
    $req.Timeout = 300000
    $req.ReadWriteTimeout = 900000
    $req.Headers.Add('Authorization', $autorizacao)
    $req.Headers.Add('x-amz-content-sha256', $hashConteudo)
    $req.Headers.Add('x-amz-date', $dataHora)
    if ($CabecalhosExtra) {
        foreach ($nome in $CabecalhosExtra.Keys) {
            if ($nome.ToLower() -eq 'content-type') { $req.ContentType = $CabecalhosExtra[$nome] }
            else { $req.Headers.Add($nome, $CabecalhosExtra[$nome]) }
        }
    }

    if ($ArquivoCorpo) {
        $fi = Get-Item -LiteralPath $ArquivoCorpo
        $req.ContentLength = $fi.Length
        $req.AllowWriteStreamBuffering = $false
        $entrada = [IO.File]::Open($ArquivoCorpo, 'Open', 'Read', 'ReadWrite')
        try {
            $saida = $req.GetRequestStream()
            try { $entrada.CopyTo($saida, 1MB) } finally { $saida.Close() }
        } finally { $entrada.Close() }
    } elseif ($Corpo -and $Corpo.Length -gt 0) {
        $req.ContentLength = $Corpo.Length
        $saida = $req.GetRequestStream()
        try { $saida.Write($Corpo, 0, $Corpo.Length) } finally { $saida.Close() }
    } elseif ($Metodo -ne 'GET' -and $Metodo -ne 'HEAD') {
        $req.ContentLength = 0
    }

    try {
        $resp = $req.GetResponse()
        $leitor = New-Object IO.StreamReader($resp.GetResponseStream())
        $texto = $leitor.ReadToEnd()
        $cabResp = @{}
        foreach ($n in $resp.Headers.AllKeys) { $cabResp[$n] = $resp.Headers[$n] }
        $leitor.Close(); $resp.Close()
        return [PSCustomObject]@{ Corpo = $texto; Cabecalhos = $cabResp }
    } catch [Net.WebException] {
        $detalhe = ''
        if ($_.Exception.Response) {
            $l = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream())
            $detalhe = $l.ReadToEnd(); $l.Close()
            if ($detalhe -match '<Message>(.*?)</Message>') { $detalhe = $Matches[1] }
        }
        throw "AWS recusou ($Metodo $Chave): $detalhe$(if (-not $detalhe) { $_.Exception.Message })"
    }
}

# --- envio de um arquivo ------------------------------------------------------

$LIMITE_PARTE = 256MB   # acima disso vai em partes, com retomada por parte

<#
    Repete com espera crescente. Em 100 cartorios, com links domesticos e
    616 GB para subir, erro de rede nao e excecao: e rotina. Sem isto, uma
    oscilacao de dez segundos derruba a copia da noite inteira.

    Repete so o que adianta repetir: erro de rede, limite de taxa da Amazon
    (503 SlowDown) e erro interno dela (500). Credencial errada ou bucket
    inexistente falham na hora - insistir so atrasaria o diagnostico.
#>
function Repetir([scriptblock]$acao, [string]$oQue, [int]$tentativas = 5) {
    $espera = 2
    for ($n = 1; ; $n++) {
        try { return & $acao }
        catch {
            $m = $_.Exception.Message
            $vaiAdiantar = $m -match 'SlowDown|RequestTimeout|InternalError|ServiceUnavailable|' +
                                     'conexao|connection|timed out|timeout|502|503|500'
            if (-not $vaiAdiantar -or $n -ge $tentativas) { throw }
            Nota "tentativa $n falhou ($oQue), repetindo em $espera s"
            Start-Sleep -Seconds $espera
            $espera = [Math]::Min($espera * 2, 60)
        }
    }
}

# Segura o ritmo para nao ocupar o link inteiro do cartorio.
$script:BytesNaJanela = 0
$script:InicioJanela = [DateTime]::UtcNow

function Segurar([double]$bytes) {
    if ($script:LimiteBps -le 0) { return }
    $script:BytesNaJanela += $bytes
    $decorrido = ([DateTime]::UtcNow - $script:InicioJanela).TotalSeconds
    $devido = $script:BytesNaJanela / $script:LimiteBps
    if ($devido -gt $decorrido) { Start-Sleep -Milliseconds ([int](($devido - $decorrido) * 1000)) }
    if ($decorrido -gt 30) { $script:BytesNaJanela = 0; $script:InicioJanela = [DateTime]::UtcNow }
}

function EnviarArquivo([string]$caminhoLocal, [string]$chaveRemota) {
    $cabComuns = @{ 'x-amz-server-side-encryption' = 'AES256' }
    $tam = (Get-Item -LiteralPath $caminhoLocal).Length

    if ($tam -le $LIMITE_PARTE) {
        Repetir { ChamarS3 -Metodo 'PUT' -Chave $chaveRemota -ArquivoCorpo $caminhoLocal `
                           -CabecalhosExtra $cabComuns -SemAssinarConteudo | Out-Null
        } ([IO.Path]::GetFileName($caminhoLocal))
        Segurar $tam
        return
    }

    # --- envio em partes ---
    $r = ChamarS3 -Metodo 'POST' -Chave $chaveRemota -Consulta 'uploads=' -CabecalhosExtra $cabComuns
    if ($r.Corpo -notmatch '<UploadId>(.*?)</UploadId>') { throw "AWS nao devolveu UploadId para $chaveRemota" }
    $idEnvio = $Matches[1]

    $partes = @()
    $numero = 1
    $entrada = [IO.File]::Open($caminhoLocal, 'Open', 'Read', 'ReadWrite')
    $temp = Join-Path $env:TEMP ('chcom-parte-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $buffer = New-Object byte[] $LIMITE_PARTE
        while ($true) {
            $lidos = $entrada.Read($buffer, 0, $buffer.Length)
            if ($lidos -le 0) { break }
            [IO.File]::WriteAllBytes($temp, $buffer[0..($lidos - 1)])
            $n = $numero
            $rp = Repetir { ChamarS3 -Metodo 'PUT' -Chave $chaveRemota `
                    -Consulta "partNumber=$n&uploadId=$idEnvio" `
                    -ArquivoCorpo $temp -SemAssinarConteudo } "parte $n"
            Segurar $lidos
            $etag = $rp.Cabecalhos['ETag']
            $partes += "<Part><PartNumber>$numero</PartNumber><ETag>$etag</ETag></Part>"
            $numero++
        }
    } catch {
        # aborta para nao deixar pedaco pago no bucket
        try { ChamarS3 -Metodo 'DELETE' -Chave $chaveRemota -Consulta "uploadId=$idEnvio" | Out-Null } catch { }
        throw
    } finally {
        $entrada.Close()
        Remove-Item $temp -Force -ErrorAction SilentlyContinue
    }

    $xml = "<CompleteMultipartUpload>$($partes -join '')</CompleteMultipartUpload>"
    ChamarS3 -Metodo 'POST' -Chave $chaveRemota -Consulta "uploadId=$idEnvio" `
             -Corpo ([Text.Encoding]::UTF8.GetBytes($xml)) `
             -CabecalhosExtra @{ 'content-type' = 'application/xml' } | Out-Null
}

function EnviarTexto([string]$texto, [string]$chaveRemota) {
    # BOM para o Bloco de Notas do Windows acertar os acentos
    $bytes = [Text.Encoding]::UTF8.GetPreamble() + [Text.Encoding]::UTF8.GetBytes($texto)
    ChamarS3 -Metodo 'PUT' -Chave $chaveRemota -Corpo $bytes `
             -CabecalhosExtra @{ 'x-amz-server-side-encryption' = 'AES256'
                                 'content-type' = 'text/plain; charset=utf-8' } | Out-Null
}

# ==============================================================================
#  CONFIGURACAO
# ==============================================================================

function PedirTexto([string]$titulo, [string]$rotulo, [switch]$Secreto) {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $f = New-Object Windows.Forms.Form
    $f.Text = $titulo; $f.Size = New-Object Drawing.Size(480, 175)
    $f.StartPosition = 'CenterScreen'; $f.TopMost = $true
    $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false

    $l = New-Object Windows.Forms.Label
    $l.Text = $rotulo
    $l.Location = New-Object Drawing.Point(14, 14); $l.Size = New-Object Drawing.Size(440, 34)
    $f.Controls.Add($l)

    $t = New-Object Windows.Forms.TextBox
    if ($Secreto) { $t.UseSystemPasswordChar = $true }
    $t.Location = New-Object Drawing.Point(14, 52); $t.Size = New-Object Drawing.Size(440, 24)
    $f.Controls.Add($t)

    $b = New-Object Windows.Forms.Button
    $b.Text = 'OK'; $b.Location = New-Object Drawing.Point(280, 90); $b.Size = New-Object Drawing.Size(80, 28)
    $b.DialogResult = 'OK'; $f.Controls.Add($b); $f.AcceptButton = $b

    $c = New-Object Windows.Forms.Button
    $c.Text = 'Cancelar'; $c.Location = New-Object Drawing.Point(368, 90); $c.Size = New-Object Drawing.Size(86, 28)
    $c.DialogResult = 'Cancel'; $f.Controls.Add($c); $f.CancelButton = $c

    $f.Add_Shown({ $t.Focus() })
    if ($f.ShowDialog() -ne 'OK') { return $null }
    return $t.Text
}

function Configurar {
    Titulo "Configuracao da copia por pastas"

    if (-not (Test-Path $PastaEstado)) { New-Item -ItemType Directory -Force $PastaEstado | Out-Null }

    # Cada campo vem do parametro quando ele foi passado; so o que faltar e
    # perguntado. Passando todos, roda calado - que e o modo de implantar em
    # 100 maquinas.
    $bucket = $Bucket
    if (-not $bucket) { $bucket = PedirTexto 'CH.Com Backup - AWS' 'Nome do bucket na AWS (so o nome, sem s3:// e sem barra):' }
    if (-not $bucket) { Aviso 'cancelado.'; return }

    $regiao = $Regiao
    if (-not $regiao) { $regiao = PedirTexto 'CH.Com Backup - AWS' 'Regiao do bucket (ex.: sa-east-1 para Sao Paulo):' }
    if (-not $regiao) { Aviso 'cancelado.'; return }

    $prefixo = $Prefixo
    if (-not $prefixo) { $prefixo = PedirTexto 'CH.Com Backup - AWS' 'Nome do cartorio (vira a pasta raiz na AWS). Ex.: CARTORIO-SAO-MIGUEL' }
    if (-not $prefixo) { Aviso 'cancelado.'; return }

    $origem = if ($Origem) { $Origem -join ';' } else { $null }
    if (-not $origem) { $origem = PedirTexto 'CH.Com Backup - AWS' 'Pastas a copiar, separadas por ponto e virgula. Ex.: C:\Dados;D:\Cartorio' }
    if (-not $origem) { Aviso 'cancelado.'; return }

    $chave = $ChaveAws
    if (-not $chave) { $chave = PedirTexto 'CH.Com Backup - AWS' 'Access Key ID da AWS:' }
    if (-not $chave) { Aviso 'cancelado.'; return }

    $segredo = $SegredoAws
    if (-not $segredo) { $segredo = PedirTexto 'CH.Com Backup - AWS' 'Secret Access Key da AWS:' -Secreto }
    if (-not $segredo) { Aviso 'cancelado.'; return }

    # A chave secreta e gravada protegida pelo DPAPI da maquina: so processos
    # DESTA maquina conseguem ler. Copiar o arquivo para outro computador nao
    # serve de nada.
    Add-Type -AssemblyName System.Security
    $segredoProtegido = [Convert]::ToBase64String(
        [Security.Cryptography.ProtectedData]::Protect(
            [Text.Encoding]::UTF8.GetBytes($segredo),
            $null,
            [Security.Cryptography.DataProtectionScope]::LocalMachine))

    @{
        Bucket     = $bucket.Trim()
        Regiao     = $regiao.Trim()
        Prefixo    = $prefixo.Trim().Trim('/')
        Origem     = @($origem.Split(';') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        Chave      = $chave.Trim()
        Segredo    = $segredoProtegido
        UrlPainel  = if ($UrlPainel) { $UrlPainel.TrimEnd('/') } else { '' }
        Token      = if ($Token) { $Token.Trim() } else { '' }
        LimiteMbps = $LimiteMbps
    } | ConvertTo-Json | Set-Content -Path $ArquivoConfig -Encoding UTF8

    $segredo = $null; [GC]::Collect()

    Ok "configuracao gravada em $ArquivoConfig"
    Nota "a chave secreta ficou protegida pelo Windows, so legivel nesta maquina"
    Write-Host ""
    Nota "Agora rode:  .\backup-pastas-aws.ps1 -Testar"
}

function CarregarConfig {
    if (-not (Test-Path $ArquivoConfig)) {
        throw "sem configuracao. Rode primeiro: .\backup-pastas-aws.ps1 -Configurar"
    }
    Add-Type -AssemblyName System.Security
    $c = Get-Content $ArquivoConfig -Raw -Encoding UTF8 | ConvertFrom-Json
    $segredo = [Text.Encoding]::UTF8.GetString(
        [Security.Cryptography.ProtectedData]::Unprotect(
            [Convert]::FromBase64String($c.Segredo), $null,
            [Security.Cryptography.DataProtectionScope]::LocalMachine))
    return [PSCustomObject]@{
        Bucket = $c.Bucket; Regiao = $c.Regiao; Prefixo = $c.Prefixo
        Origem = @($c.Origem); Chave = $c.Chave; Segredo = $segredo
        UrlPainel = "$($c.UrlPainel)"; Token = "$($c.Token)"
        LimiteMbps = [double]("0" + "$($c.LimiteMbps)")
    }
}

<#
    Relatorio para o painel central.

    Vai no mesmo formato que o Duplicati manda, porque o painel ja sabe ler
    esse formato (aceita tanto "Data.X" quanto "X"). Assim os 100 cartorios
    aparecem numa tela so, sem precisar mexer no painel.

    Falha aqui nao pode derrubar nada: a copia ja foi feita, o relatorio e
    consequencia. So avisa e segue.
#>
function Reportar($cfg, $dados) {
    if (-not $cfg.UrlPainel -or -not $cfg.Token) { return }
    try {
        $corpo = @{
            Data = @{
                MainOperation       = 'Backup'
                ParsedResult        = $dados.Resultado
                BeginTime           = $dados.Inicio.ToString('o')
                EndTime             = $dados.Fim.ToString('o')
                Duration            = ([TimeSpan]($dados.Fim - $dados.Inicio)).ToString('c')
                SizeOfExaminedFiles = $dados.BytesOrigem
                ExaminedFiles       = $dados.ArquivosOrigem
                WarningsActualLength = $dados.Bloqueados
                ErrorsActualLength   = $dados.Falhas
                Errors              = @($dados.TextoFalhas)
                Warnings            = @($dados.TextoAvisos)
                BackendStatistics   = @{
                    BytesUploaded = $dados.BytesEnviados
                    KnownFileSize = $dados.BytesTotalNaNuvem
                }
            }
            Extra = @{
                'backup-name'  = "$($cfg.Prefixo) (copia por pastas)"
                'machine-name' = $env:COMPUTERNAME
                'pasta-do-dia' = $dados.Pasta
            }
        } | ConvertTo-Json -Depth 8

        Invoke-RestMethod "$($cfg.UrlPainel)/api/report/$($cfg.Token)" -Method Post `
            -ContentType 'application/json' -Body $corpo -TimeoutSec 30 | Out-Null
        Ok "relatorio enviado ao painel"
    } catch {
        Aviso "nao consegui avisar o painel: $($_.Exception.Message)"
    }
}

# ==============================================================================
#  TESTE DE LIGACAO
# ==============================================================================

function Testar {
    $script:Config = CarregarConfig
    Titulo "Testando a ligacao com a AWS"
    Nota "bucket: $($script:Config.Bucket)  regiao: $($script:Config.Regiao)"

    $chave = "$($script:Config.Prefixo)/TESTE-CH-COM.txt"
    $texto = "Teste do CH.Com Backup em $((Get-Date).ToString('dd/MM/yyyy HH:mm:ss')).`r`n" +
             "Se voce esta lendo isto no console da AWS, a ligacao funciona.`r`n"

    try {
        EnviarTexto $texto $chave
        Ok "enviou"
    } catch { Erro $_.Exception.Message; return 1 }

    try {
        $r = ChamarS3 -Metodo 'GET' -Chave $chave
        if ($r.Corpo -match 'CH\.Com Backup') { Ok "leu de volta - assinatura e credencial corretas" }
        else { Erro "leu algo diferente do que enviou"; return 1 }
    } catch { Erro $_.Exception.Message; return 1 }

    Write-Host ""
    Ok "LIGACAO OK."
    Nota "Confira no console da AWS: $($script:Config.Bucket)/$($script:Config.Prefixo)/TESTE-CH-COM.txt"
    return 0
}

# ==============================================================================
#  EXECUCAO
# ==============================================================================

function CarregarIndice {
    if (-not (Test-Path $ArquivoIndice)) { return @{} }
    try {
        $j = Get-Content $ArquivoIndice -Raw -Encoding UTF8 | ConvertFrom-Json
        $h = @{}
        foreach ($p in $j.PSObject.Properties) { $h[$p.Name] = $p.Value }
        return $h
    } catch { return @{} }
}

function GravarIndice($indice) {
    if (-not (Test-Path $PastaEstado)) { New-Item -ItemType Directory -Force $PastaEstado | Out-Null }
    $indice | ConvertTo-Json -Depth 4 -Compress | Set-Content -Path $ArquivoIndice -Encoding UTF8
}

<#
    Caminho do arquivo dentro da pasta do dia. "C:\Dados\x.pdf" vira
    "C/Dados/x.pdf": mantem a arvore, tira os dois-pontos que o S3 nao aceita
    bem em chave, e deixa navegavel no console.
#>
function CaminhoRelativo([string]$completo) {
    $c = $completo -replace '^([A-Za-z]):\\', '$1/'
    return ($c -replace '\\', '/')
}

function Executar {
    $script:Config = CarregarConfig
    $inicio = Get-Date

    # limite de banda: megabits por segundo -> bytes por segundo
    $mbps = if ($LimiteMbps -gt 0) { $LimiteMbps } else { $script:Config.LimiteMbps }
    $script:LimiteBps = if ($mbps -gt 0) { ($mbps * 1000000) / 8 } else { 0 }
    if ($script:LimiteBps -gt 0) { Nota "limite de banda: $mbps Mbps" }

    $indice = CarregarIndice
    $primeiraVez = ($indice.Count -eq 0)

    $pasta = if ($primeiraVez) { 'BACKUP-FULL' }
             else { 'BACKUP-INCREMENTAL-' + (Get-Date).ToString('dd-MM-yyyy') }

    Titulo "Copia para a AWS - $pasta"
    Nota "origem: $($script:Config.Origem -join ' ; ')"

    # --- levanta o que existe hoje na origem ---------------------------------
    $candidatos = @()
    foreach ($raiz in $script:Config.Origem) {
        if (-not (Test-Path $raiz)) { Aviso "origem nao encontrada, pulando: $raiz"; continue }
        Get-ChildItem -LiteralPath $raiz -Recurse -File -Force -ErrorAction SilentlyContinue |
            ForEach-Object { $candidatos += $_ }
    }
    Nota "$($candidatos.Count) arquivo(s) na origem"

    # --- decide o que subir ---------------------------------------------------
    $aEnviar = @()
    foreach ($f in $candidatos) {
        $ja = $indice[$f.FullName]
        $mudou = $true
        if ($ja) {
            $mudou = ($ja.Tamanho -ne $f.Length) -or
                     ($ja.Alterado -ne $f.LastWriteTimeUtc.ToString('o'))
        }
        if ($mudou) { $aEnviar += $f }
    }

    $totalBytes = ($aEnviar | Measure-Object -Property Length -Sum).Sum
    if (-not $totalBytes) { $totalBytes = 0 }
    Nota "$($aEnviar.Count) arquivo(s) novos ou alterados - $(Bytes $totalBytes)"

    # --- apagados na origem ---------------------------------------------------
    $vivos = @{}
    foreach ($f in $candidatos) { $vivos[$f.FullName] = $true }
    $sumidos = @($indice.Keys | Where-Object { -not $vivos.ContainsKey($_) })

    if ($Simular) {
        Titulo "SIMULACAO - nada foi enviado"
        Nota "pasta de destino: $($script:Config.Prefixo)/$pasta/"
        $aEnviar | Select-Object -First 25 | ForEach-Object {
            Write-Host ("      " + (CaminhoRelativo $_.FullName) + "   " + (Bytes $_.Length))
        }
        if ($aEnviar.Count -gt 25) { Nota "... e mais $($aEnviar.Count - 25) arquivo(s)" }
        if ($sumidos.Count -gt 0) { Nota "$($sumidos.Count) arquivo(s) sumiram da origem (ficam na nuvem)" }
        return 0
    }

    # --- envia ----------------------------------------------------------------
    $enviados = 0; $bytesEnviados = 0; $falhas = @(); $bloqueados = @()
    $linhasCsv = New-Object Collections.Generic.List[string]
    $linhasCsv.Add('caminho;tamanho_bytes;alterado_em')

    $i = 0
    foreach ($f in $aEnviar) {
        $i++
        $rel = CaminhoRelativo $f.FullName
        $chave = "$($script:Config.Prefixo)/$pasta/$rel"
        try {
            EnviarArquivo $f.FullName $chave
            $indice[$f.FullName] = @{
                Tamanho  = $f.Length
                Alterado = $f.LastWriteTimeUtc.ToString('o')
                Pasta    = $pasta
            }
            $enviados++; $bytesEnviados += $f.Length
            $linhasCsv.Add("$rel;$($f.Length);$($f.LastWriteTime.ToString('dd/MM/yyyy HH:mm:ss'))")

            if ($i % 50 -eq 0) {
                Nota "$i de $($aEnviar.Count) - $(Bytes $bytesEnviados) enviados"
                GravarIndice $indice   # salva o progresso: queda de link nao perde tudo
            }
        } catch {
            $msg = $_.Exception.Message
            if ($msg -match 'being used by another process|denied') { $bloqueados += $f.FullName }
            else { $falhas += "$rel :: $msg" }
        }
    }

    GravarIndice $indice

    # --- resumo e lista na propria pasta --------------------------------------
    $resumo = @(
        '=============================================================='
        "  $pasta"
        '=============================================================='
        ''
        "  Data e hora        : $((Get-Date).ToString('dd/MM/yyyy HH:mm:ss'))"
        "  Pastas de origem   : $($script:Config.Origem -join ' ; ')"
        ''
        "  Arquivos enviados  : $('{0:N0}' -f $enviados)"
        "  Volume enviado     : $(Bytes $bytesEnviados)"
        "  Arquivos na origem : $('{0:N0}' -f $candidatos.Count)"
        ''
    )
    if ($bloqueados.Count -gt 0) {
        $resumo += "  NAO FOI POSSIVEL LER $($bloqueados.Count) ARQUIVO(S) - estavam abertos por"
        $resumo += "  outro programa no momento da copia:"
        foreach ($b in ($bloqueados | Select-Object -First 20)) { $resumo += "    - $b" }
        if ($bloqueados.Count -gt 20) { $resumo += "    ... e mais $($bloqueados.Count - 20)" }
        $resumo += ''
    }
    if ($falhas.Count -gt 0) {
        $resumo += "  FALHAS ($($falhas.Count)):"
        foreach ($x in ($falhas | Select-Object -First 20)) { $resumo += "    - $x" }
        $resumo += ''
    }
    if ($sumidos.Count -gt 0) {
        $resumo += "  $($sumidos.Count) arquivo(s) nao existem mais na origem."
        $resumo += "  Eles continuam guardados nas pastas anteriores desta nuvem."
        $resumo += ''
    }
    $resumo += @(
        '  --------------------------------------------------------------'
        '  BACKUP-FULL tem a carga inteira. Cada BACKUP-INCREMENTAL-DATA'
        '  tem so o que mudou naquele dia. Para achar a versao mais nova de'
        '  um arquivo, procure da pasta mais recente para a mais antiga.'
        '  --------------------------------------------------------------'
        '  CH.Com Solucoes em Tecnologia'
        ''
    )

    try {
        EnviarTexto ($resumo -join "`r`n") "$($script:Config.Prefixo)/$pasta/RESUMO.txt"
        EnviarTexto ($linhasCsv -join "`r`n") "$($script:Config.Prefixo)/$pasta/LISTA.csv"
    } catch { Aviso "nao consegui publicar o resumo: $($_.Exception.Message)" }

    # --- total acumulado na nuvem (soma do indice) ----------------------------
    $totalNaNuvem = 0
    foreach ($v in $indice.Values) { $totalNaNuvem += [double]$v.Tamanho }

    Reportar $script:Config @{
        Resultado         = if ($falhas.Count -gt 0) { 'Error' }
                            elseif ($bloqueados.Count -gt 0) { 'Warning' }
                            else { 'Success' }
        Inicio            = $inicio
        Fim               = (Get-Date)
        BytesEnviados     = $bytesEnviados
        BytesTotalNaNuvem = $totalNaNuvem
        BytesOrigem       = (($candidatos | Measure-Object -Property Length -Sum).Sum)
        ArquivosOrigem    = $candidatos.Count
        Falhas            = $falhas.Count
        Bloqueados        = $bloqueados.Count
        TextoFalhas       = @($falhas | Select-Object -First 8)
        TextoAvisos       = @($bloqueados | Select-Object -First 8 |
                              ForEach-Object { "Arquivo aberto por outro programa: $_" })
        Pasta             = $pasta
    }

    Write-Host ""
    Ok "$enviados arquivo(s) enviados - $(Bytes $bytesEnviados)"
    if ($bloqueados.Count -gt 0) { Aviso "$($bloqueados.Count) arquivo(s) estavam abertos e nao puderam ser lidos" }
    if ($falhas.Count -gt 0) { Erro "$($falhas.Count) falha(s) - detalhes no RESUMO.txt da pasta" }
    Nota "pasta na AWS: $($script:Config.Bucket)/$($script:Config.Prefixo)/$pasta/"

    return $(if ($falhas.Count -gt 0) { 2 } else { 0 })
}

# ==============================================================================
#  AGENDAMENTO
# ==============================================================================

function Instalar {
    Titulo "Agendando a copia diaria"

    $meu = $PSCommandPath
    if (-not $meu) { $meu = $MyInvocation.MyCommand.Path }
    $destino = Join-Path $PastaEstado 'backup-pastas-aws.ps1'
    if (-not (Test-Path $PastaEstado)) { New-Item -ItemType Directory -Force $PastaEstado | Out-Null }
    Copy-Item $meu $destino -Force

    $acao = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$destino`""
    $gatilho = New-ScheduledTaskTrigger -Daily -At $Hora
    $conf = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd `
        -ExecutionTimeLimit ([TimeSpan]::FromHours(20))

    try {
        Register-ScheduledTask -TaskName 'CH.Com Backup - copia por pastas na AWS' `
            -Action $acao -Trigger $gatilho -Settings $conf `
            -RunLevel Highest -User 'SYSTEM' -Force | Out-Null
        Ok "agendado para todo dia as $Hora"
    } catch {
        Erro "nao consegui agendar: $($_.Exception.Message)"
        Nota "rode este script como Administrador."
        return 1
    }
    return 0
}

# ==============================================================================

try {
    if ($Configurar) { Configurar; exit 0 }
    if ($Testar)     { exit (Testar) }
    if ($Instalar)   { exit (Instalar) }
    exit (Executar)
} catch {
    Erro $_.Exception.Message
    exit 1
}
