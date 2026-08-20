<#
================================================================================
  CH.Com Backup - resumo dos avisos

  ESTE SCRIPT RODA NO SERVIDOR DO CARTORIO, NAO NA SUA MAQUINA.

  PARA QUE SERVE

  Um log de backup tem milhares de linhas, e quase tudo la e a mesma coisa
  repetida centenas de vezes. Ler aquilo nao ajuda ninguem, e mandar aquilo
  para alguem ajuda menos ainda.

  Este script le os relatorios que o proprio programa ja guardou e mostra os
  avisos AGRUPADOS: que tipo, quantas vezes, e um exemplo de cada. Cabe numa
  tela. Da para tirar print e mandar.

  Ele NAO le arquivo de log e NAO precisa que ninguem ligue log nenhum antes:
  pergunta direto ao programa, os mesmos relatorios que aparecem na tela de
  historico.

  USO

      Dois cliques em RESUMIR-AVISOS.bat, no servidor do cartorio.

================================================================================
#>

[CmdletBinding()]
param(
    [int]$PortaDuplicati = 8200,

    # Quantas execucoes olhar para tras.
    [int]$Execucoes = 10
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Titulo($t) { Write-Host ""; Write-Host "  $t" -ForegroundColor Cyan }
function Ok($t)     { Write-Host "    $t" -ForegroundColor Green }
function Aviso($t)  { Write-Host "    $t" -ForegroundColor Yellow }
function Erro($t)   { Write-Host "    $t" -ForegroundColor Red }
function Nota($t)   { Write-Host "    $t" -ForegroundColor DarkGray }


# Desliga o modo de selecao do console. Um clique dentro da janela congela o
# script ate alguem apertar Esc - e aqui existe uma pergunta de senha, entao
# quem estivesse no servidor acharia que travou.
function DesligarCliqueQueTrava {
    try {
        if (-not ('ChCom.ModoDoConsole' -as [type])) {
            Add-Type -Name 'ModoDoConsole' -Namespace 'ChCom' -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)]
public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
'@
        }
        $h = [ChCom.ModoDoConsole]::GetStdHandle(-10)
        $modo = 0
        if ([ChCom.ModoDoConsole]::GetConsoleMode($h, [ref]$modo)) {
            [void][ChCom.ModoDoConsole]::SetConsoleMode($h, ($modo -band (-bnot 0x40)) -bor 0x80)
        }
    } catch { }
}
DesligarCliqueQueTrava


function PedirSenha {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing

    $f = New-Object Windows.Forms.Form
    $f.Text = 'CH.Com Backup'
    $f.Size = New-Object Drawing.Size(450, 180)
    $f.StartPosition = 'CenterScreen'
    $f.FormBorderStyle = 'FixedDialog'
    $f.MaximizeBox = $false; $f.MinimizeBox = $false; $f.TopMost = $true

    $l = New-Object Windows.Forms.Label
    $l.Text = 'Senha de acesso ao CH.Com Backup deste servidor:'
    $l.Location = New-Object Drawing.Point(16, 18)
    $l.Size = New-Object Drawing.Size(404, 20)
    $f.Controls.Add($l)

    $t = New-Object Windows.Forms.TextBox
    $t.UseSystemPasswordChar = $true
    $t.Location = New-Object Drawing.Point(16, 46)
    $t.Size = New-Object Drawing.Size(404, 24)
    $f.Controls.Add($t)

    $ok = New-Object Windows.Forms.Button
    $ok.Text = 'OK'
    $ok.Location = New-Object Drawing.Point(246, 86)
    $ok.Size = New-Object Drawing.Size(84, 30)
    $ok.DialogResult = 'OK'
    $f.Controls.Add($ok); $f.AcceptButton = $ok

    $c = New-Object Windows.Forms.Button
    $c.Text = 'Cancelar'
    $c.Location = New-Object Drawing.Point(336, 86)
    $c.Size = New-Object Drawing.Size(84, 30)
    $c.DialogResult = 'Cancel'
    $f.Controls.Add($c); $f.CancelButton = $c

    $f.Add_Shown({ $t.Focus() })
    if ($f.ShowDialog() -ne 'OK') { return $null }
    return $t.Text
}


<#
    Reduz uma linha de aviso ao seu TIPO.

    O programa escreve cada aviso mais ou menos assim:

      2026-08-19 21:01:34 -04 - [Warning-Duplicati.Library.Main...-PermissionDenied]:
      Excluding path due to permission denied: C:\Windows\CSC\v2.0.6\...

    O que muda de uma linha para a outra e o CAMINHO. O que interessa e a
    etiqueta entre colchetes - PermissionDenied, UnsupportedOption, e por ai.
    E assim que vinte linhas viram uma so:

      20x  PermissionDenied
           Excluding path due to permission denied: C:\Windows\CSC\...
#>
# Tira a data do comeco da linha.
#
# Nao vale a pena regex aqui: o carimbo do Duplicati e
# "2026-08-19 21:01:34 -04 - " e o "-04" do fuso confunde qualquer recorte
# esperto. O separador de verdade e o primeiro " - ", e ele sempre aparece
# nos primeiros 40 caracteres.
function SemData([string]$linha) {
    $p = $linha.IndexOf(' - ')
    if ($p -gt 0 -and $p -lt 40) { return $linha.Substring($p + 3) }
    return $linha
}

function TipoDoAviso([string]$linha) {
    if ($linha -match '\[(?:Warning|Error)-[^\]]*?-([A-Za-z][A-Za-z0-9]*)\]') { return $Matches[1] }
    if ($linha -match '\[(?:Warning|Error)-([^\]]+)\]')                       { return $Matches[1] }

    # Sem etiqueta: usa o comeco da frase.
    $corte = ((SemData $linha) -split ':')[0]
    if ($corte.Length -gt 60) { $corte = $corte.Substring(0, 60) }
    return $corte.Trim()
}

function TrechoUtil([string]$linha) {
    $t = SemData $linha
    $t = $t -replace '\[[^\]]+\]:\s*', ''
    $t = ($t -split "`n")[0]
    return $t.Trim()
}


# ==============================================================================

Titulo 'Resumo dos avisos do backup'

$base = "http://127.0.0.1:$PortaDuplicati"

try {
    $c = New-Object Net.Sockets.TcpClient
    $c.Connect('127.0.0.1', $PortaDuplicati)
    $c.Close()
} catch {
    Erro "o CH.Com Backup nao esta respondendo na porta $PortaDuplicati."
    Nota 'Abra o programa pelo icone ao lado do relogio e rode isto de novo.'
    Write-Host ""
    exit 1
}

$senha = PedirSenha
if (-not $senha) { Aviso 'cancelado.'; exit 0 }

try {
    $login = Invoke-RestMethod "$base/api/v1/auth/login" -Method Post -TimeoutSec 20 `
        -ContentType 'application/json' `
        -Body (@{ Password = $senha; RememberMe = $false } | ConvertTo-Json)
} catch {
    Erro 'senha recusada.'
    Nota 'Se ninguem definiu senha neste servidor, rode antes o DEFINIR-SENHA.bat.'
    Write-Host ""
    exit 1
} finally {
    $senha = $null
    [GC]::Collect()
}

$cabecalho = @{ Authorization = "Bearer $($login.AccessToken)" }
$lista = @(Invoke-RestMethod "$base/api/v1/backups" -Headers $cabecalho -TimeoutSec 20)

if ($lista.Count -eq 0) {
    Aviso 'nao ha nenhum backup configurado neste servidor.'
    Write-Host ""
    exit 0
}

foreach ($item in $lista) {
    $id = $item.Backup.ID
    if (-not $id) { continue }

    Titulo ("Backup: " + $item.Backup.Name)

    try {
        $log = @(Invoke-RestMethod "$base/api/v1/backup/$id/log?pagesize=200" `
            -Headers $cabecalho -TimeoutSec 60)
    } catch {
        Erro "nao consegui ler o historico deste backup: $($_.Exception.Message)"
        continue
    }

    # Cada linha de tipo Result e uma execucao inteira, gravada em JSON, com as
    # listas Warnings e Errors dentro. E dai que sai tudo - sem log nenhum.
    $execucoes = @()
    foreach ($linhaLog in $log) {
        if ($linhaLog.Type -ne 'Result' -or -not $linhaLog.Message) { continue }
        try { $r = $linhaLog.Message | ConvertFrom-Json } catch { continue }
        if ($r.MainOperation -ne 'Backup') { continue }
        $execucoes += $r
        if ($execucoes.Count -ge $Execucoes) { break }
    }

    if ($execucoes.Count -eq 0) {
        Nota 'nenhuma execucao registrada ainda'
        continue
    }
    Nota "olhando as ultimas $($execucoes.Count) execucoes"

    # --- agrupa -------------------------------------------------------------
    $tipos = @{}
    foreach ($ex in $execucoes) {
        foreach ($grupo in @(
            [PSCustomObject]@{ Nome = 'ERRO';  Linhas = $ex.Errors   },
            [PSCustomObject]@{ Nome = 'aviso'; Linhas = $ex.Warnings }
        )) {
            foreach ($linha in @($grupo.Linhas)) {
                if (-not $linha) { continue }
                $texto = [string]$linha
                $tipo  = TipoDoAviso $texto
                $chave = $grupo.Nome + '|' + $tipo

                if (-not $tipos.ContainsKey($chave)) {
                    $tipos[$chave] = [PSCustomObject]@{
                        Gravidade = $grupo.Nome
                        Tipo      = $tipo
                        Vezes     = 0
                        Exemplo   = (TrechoUtil $texto)
                    }
                }
                $tipos[$chave].Vezes++
            }
        }
    }

    if ($tipos.Count -eq 0) {
        Ok 'nenhum aviso nas execucoes analisadas'
        continue
    }

    # erro antes de aviso; dentro de cada um, o mais frequente primeiro
    $ordenado = @($tipos.Values | Sort-Object `
        @{ Expression = { if ($_.Gravidade -eq 'ERRO') { 0 } else { 1 } } }, `
        @{ Expression = 'Vezes'; Descending = $true })

    Write-Host ""
    foreach ($t in $ordenado) {
        $cor = if ($t.Gravidade -eq 'ERRO') { 'Red' } else { 'Yellow' }
        Write-Host ("    {0,5}x  " -f $t.Vezes) -ForegroundColor $cor -NoNewline
        Write-Host $t.Tipo -ForegroundColor White
        $ex = $t.Exemplo
        if ($ex.Length -gt 96) { $ex = $ex.Substring(0, 96) + '...' }
        Write-Host "           $ex" -ForegroundColor DarkGray
    }

    # --- o que fazer --------------------------------------------------------
    $textoTudo = ($ordenado | ForEach-Object { $_.Tipo + ' ' + $_.Exemplo }) -join "`n"

    $opcaoInvalida = $textoTudo -match 'UnsupportedOption|-{3,}'
    $permissao     = $textoTudo -match 'PermissionDenied|permission denied'
    $travado       = $textoTudo -match 'used by another process|being used by'
    $sumiu         = $textoTudo -match 'MissingFile|FileNotFound|did not exist'

    Write-Host ""
    Write-Host "    O QUE FAZER" -ForegroundColor Cyan

    if ($opcaoInvalida) {
        Aviso 'Ha opcao invalida gravada (nome comecando com tres tracos ou mais).'
        Nota  'E filtro que foi digitado no campo de Opcoes em vez do de Filtros.'
        Nota  'Rode o APLICAR-REGRAS.bat: ele apaga essas e grava no lugar certo.'
    }
    if ($permissao) {
        Aviso 'Ha arquivos do proprio Windows sendo lidos e negados.'
        Nota  'Rode o APLICAR-REGRAS.bat: o filtro {OperatingSystem} tira o C:\Windows.'
    }
    if ($travado) {
        Aviso 'Ha arquivo aberto por outro programa NAO sendo copiado.'
        Nota  'E o pior caso: o backup termina verde e o dado nao esta la dentro.'
        Nota  'Rode o APLICAR-REGRAS.bat: ele liga a copia de arquivo aberto (VSS).'
    }
    if ($sumiu -and -not ($opcaoInvalida -or $permissao -or $travado)) {
        Nota 'Arquivos que sumiram no meio do backup - normal em pasta temporaria.'
    }
    if (-not ($opcaoInvalida -or $permissao -or $travado -or $sumiu)) {
        Nota 'Nada dos casos conhecidos. Tire print desta tela e mande ao suporte.'
    }
}

Write-Host ""
Nota 'Tire um print desta tela - e tudo que o suporte precisa ver.'
Write-Host ""

