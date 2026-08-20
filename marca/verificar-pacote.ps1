<#
================================================================================
  Verificacao do pacote antes de entregar.

  Nao e teste de funcionamento - isso so acontece num servidor de verdade.
  E a checagem das falhas que ja aconteceram neste projeto e que so aparecem
  depois de o pendrive estar no cartorio:

    - .ps1 com erro de sintaxe, que so quebra quando roda
    - acento em .ps1, que o PowerShell 5.1 le como ANSI e corrompe
    - .bat chamando um .ps1 que nao foi copiado
    - documento mandando rodar um arquivo que nao existe
    - arquivo do instalador faltando na pasta marca
    - segredo escapando para a pasta de entrega, que fica numa unidade de rede

  Roda em segundos e nao altera nada.
================================================================================
#>

[CmdletBinding()]
param(
    [string]$Pacote = 'C:\dev\ch-backup\branding\dist\CH.Com-Backup-Instalacao'
)

$ErrorActionPreference = 'Stop'
$problemas = @()
$avisos = @()

function Titulo($t) { Write-Host ""; Write-Host "  $t" -ForegroundColor Cyan }
function Ok($t)     { Write-Host "    [OK] $t" -ForegroundColor Green }
function Falha($t)  { Write-Host "    [X ] $t" -ForegroundColor Red;    $script:problemas += $t }
function Aviso($t)  { Write-Host "    [! ] $t" -ForegroundColor Yellow; $script:avisos += $t }

if (-not (Test-Path $Pacote)) { throw "pacote nao encontrado em $Pacote" }

# --- 1. sintaxe dos scripts --------------------------------------------------
Titulo '1. Sintaxe dos scripts'
$ps1 = @(Get-ChildItem $Pacote -Filter *.ps1 -Recurse)
foreach ($f in $ps1) {
    $erros = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$erros)
    if ($erros) {
        Falha "$($f.Name): $($erros[0].Message) (linha $($erros[0].Extent.StartLineNumber))"
    }
}
if ($problemas.Count -eq 0) { Ok "$($ps1.Count) script(s) sem erro de sintaxe" }

# --- 2. acento em script sem BOM ---------------------------------------------
#
# O PowerShell 5.1 le o proprio .ps1 usando a pagina de codigo ANSI. Um acento
# escrito ali chega corrompido, e o texto que o script imprime sai com
# "CARTA~ORIO". Ja aconteceu duas vezes neste projeto.
#
# A regra nao e "proibir acento": e "acento SO com BOM". Com BOM o PowerShell
# le como UTF-8 e tudo funciona; sem BOM, qualquer texto acentuado que alguem
# acrescentar depois sai corrompido, em silencio.
Titulo '2. Acento em script sem BOM'
$comProblema = 0
foreach ($f in ($ps1 + @(Get-ChildItem $Pacote -Filter *.bat -Recurse))) {
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    $temBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $t = [System.IO.File]::ReadAllText($f.FullName, [System.Text.UTF8Encoding]::new($false))
    $fora = [regex]::Matches($t, '[^\x00-\x7F]')
    if ($fora.Count -gt 0 -and -not $temBom) {
        $quais = ($fora | ForEach-Object { $_.Value } | Select-Object -Unique) -join ''
        Falha "$($f.Name): $($fora.Count) acento(s) [$quais] e SEM BOM - vai corromper"
        $comProblema++
    }
}
if ($comProblema -eq 0) { Ok 'todo script com acento tem BOM' }

# --- 3. cada .bat chama um .ps1 que existe -----------------------------------
Titulo '3. Os .bat apontam para scripts que existem'
$bats = @(Get-ChildItem $Pacote -Filter *.bat)
foreach ($b in $bats) {
    $t = Get-Content $b.FullName -Raw
    foreach ($m in [regex]::Matches($t, '%~dp0([A-Za-z0-9\-\._]+\.ps1)')) {
        $alvo = Join-Path $Pacote $m.Groups[1].Value
        if (-not (Test-Path $alvo)) { Falha "$($b.Name) chama $($m.Groups[1].Value), que nao esta no pacote" }
    }
}
if ($problemas.Count -eq 0) { Ok "$($bats.Count) arquivo(s) .bat com destino valido" }

# --- 4. o que o instalador espera na pasta marca -----------------------------
Titulo '4. Arquivos que o instalador vai procurar'
$aplicar = Join-Path $Pacote 'aplicar-no-cartorio.ps1'
if (-not (Test-Path $aplicar)) {
    Falha 'aplicar-no-cartorio.ps1 nao esta no pacote'
} else {
    $texto = [System.IO.File]::ReadAllText($aplicar, [System.Text.UTF8Encoding]::new($false))
    # Só as entradas da tabela de arquivos da marca: "@{ o = 'nome'; a = ... }".
    # Sem o "@{" no padrão, qualquer variável chamada $o entrava na lista e o
    # verificador acusava arquivo faltando que nunca existiu.
    $esperados = @()
    foreach ($m in [regex]::Matches($texto, "@\{\s*o\s*=\s*'([^']+)'")) { $esperados += $m.Groups[1].Value }
    $faltando = 0
    foreach ($e in ($esperados | Select-Object -Unique)) {
        if (-not (Test-Path (Join-Path $Pacote "marca\$e"))) { Falha "marca\$e nao existe (o instalador vai procurar)"; $faltando++ }
    }
    if ($faltando -eq 0) { Ok "$($esperados.Count) arquivo(s) de marca no lugar" }
}

# --- 5. documentos citando arquivos ------------------------------------------
Titulo '5. Os documentos citam arquivos que existem'
$citados = @()
foreach ($doc in (Get-ChildItem $Pacote -Include *.txt, *.md -Recurse)) {
    $t = Get-Content $doc.FullName -Raw
    foreach ($m in [regex]::Matches($t, '\b([A-Z0-9\-]+\.bat)\b')) { $citados += $m.Groups[1].Value }
}
$semArquivo = 0
foreach ($c in ($citados | Select-Object -Unique)) {
    if (-not (Test-Path (Join-Path $Pacote $c))) { Falha "documento manda rodar $c, que nao existe"; $semArquivo++ }
}
if ($semArquivo -eq 0) { Ok "$(($citados | Select-Object -Unique).Count) arquivo(s) citado(s) existem" }

# --- 6. segredos --------------------------------------------------------------
Titulo '6. Nenhum segredo no pacote'
# "senha" e "token" no NOME do arquivo nao sao segredo: DEFINIR-SENHA.bat e
# uma ferramenta, nao uma senha guardada. O que nao pode e banco, credencial
# gravada, .env e o resultado de diagnostico de outro servidor.
$risco = Get-ChildItem $Pacote -Recurse -File -Force |
    Where-Object { $_.Name -match '\.db($|-)|servidores.*\.json|\.env$|\.key$|config-aws|resultado\.txt|senha-da-chave' }
if ($risco) { foreach ($r in $risco) { Falha "arquivo sensivel no pacote: $($r.Name)" } }
else { Ok 'sem banco, senha, token ou credencial' }

# procura tambem por conteudo com cara de credencial
$vazou = 0
foreach ($f in (Get-ChildItem $Pacote -Recurse -File -Include *.ps1, *.bat, *.txt, *.md)) {
    $t = Get-Content $f.FullName -Raw
    if ($t -match 'AKIA[0-9A-Z]{16}') { Falha "$($f.Name) tem uma chave de acesso da AWS escrita dentro"; $vazou++ }
}
if ($vazou -eq 0) { Ok 'nenhuma credencial escrita dentro dos arquivos' }

# --- 7. o pacote esta completo -----------------------------------------------
Titulo '7. Pacote completo'
$obrigatorios = @('INSTALAR.bat', 'DIAGNOSTICO.bat', 'DESINSTALAR.bat', 'CORRIGIR-S3.bat',
                  'DEFINIR-SENHA.bat', 'APLICAR-REGRAS.bat', 'RESUMIR-AVISOS.bat',
                  'aplicar-no-cartorio.ps1', 'diagnostico.ps1', 'corrigir-s3.ps1',
                  'definir-senha.ps1', 'aplicar-regras.ps1', 'resumir-avisos.ps1', 'LEIA-ME.md')
$faltou = @($obrigatorios | Where-Object { -not (Test-Path (Join-Path $Pacote $_)) })
if ($faltou.Count -gt 0) { foreach ($f in $faltou) { Falha "faltando no pacote: $f" } }
else { Ok "$($obrigatorios.Count) arquivos obrigatorios presentes" }

# --- veredito ----------------------------------------------------------------
Write-Host ''
if ($problemas.Count -eq 0 -and $avisos.Count -eq 0) {
    Write-Host '  ============================================================' -ForegroundColor Green
    Write-Host '    PACOTE VERIFICADO - nada a corrigir' -ForegroundColor Green
    Write-Host '  ============================================================' -ForegroundColor Green
} elseif ($problemas.Count -eq 0) {
    Write-Host "  $($avisos.Count) aviso(s), nenhum problema." -ForegroundColor Yellow
} else {
    Write-Host '  ============================================================' -ForegroundColor Red
    Write-Host "    $($problemas.Count) PROBLEMA(S) - nao entregue assim" -ForegroundColor Red
    Write-Host '  ============================================================' -ForegroundColor Red
    foreach ($p in $problemas) { Write-Host "    - $p" -ForegroundColor Red }
}
Write-Host ''
exit $problemas.Count
