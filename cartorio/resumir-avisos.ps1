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

<#
    OS TIPOS QUE SIGNIFICAM "O ARQUIVO FICOU DE FORA".

    No codigo do Duplicati, LogExceptionHelper.LogCommonWarning escreve:

        "Excluding path due to permission denied: {0}"
        "Excluding path due to file locked: {0}"
        "Excluding path due to path not found: {0}"
        "Excluding path due to path too long: {0}"

    Excluding. O caminho NAO entra no backup. E o resultado da execucao fica
    Warning, nao Error - ou seja, o backup termina verde com o dado faltando.

    Por isso nenhum destes e "so um aviso". O que decide se importa nao e o
    tipo: e o CAMINHO.
#>
$TIPOS_QUE_EXCLUEM = @(
    'PermissionDenied', 'FileLocked', 'PathNotFound', 'PathTooLong',
    'PathProcessingFailed', 'FileProcessingFailed', 'FileAccessError'
)

<#
    Tira o caminho de dentro da mensagem.

    Sem regex de proposito. A expressao que faz isso precisa de barras
    invertidas escapadas, e barra invertida escapada e a coisa mais facil de
    perder num arquivo que passa por editor, heredoc ou copiar-e-colar - foi
    o que aconteceu aqui: uma barra sumiu, a expressao continuou casando e
    devolvendo VAZIO, e o script dizia "nenhum arquivo ficou de fora" com
    arquivos ficando de fora. Um defeito silencioso e do lado errado.

    Com metodo de texto nao ha o que escapar, e o que o codigo faz e o que
    esta escrito.

    Formatos que aparecem:
      ...permission denied: C:\Windows\CSC\ UnauthorizedAccessException: ...
      ...file locked: Z:\DADOS\base.fdb
      ...Failed to process path: C:\pagefile.sys => The process cannot access
#>
function CaminhoDoAviso([string]$linha) {
    $t = TrechoUtil $linha
    if (-not $t) { return $null }

    # Onde comeca o caminho: "X:\" (letra, dois pontos, barra) ou "\servidor"
    $inicio = -1
    for ($i = 1; $i -lt $t.Length - 1; $i++) {
        if ($t[$i] -eq ':' -and $t[$i + 1] -eq '\' -and [char]::IsLetter($t[$i - 1])) {
            $inicio = $i - 1
            break
        }
    }
    if ($inicio -lt 0) {
        $u = $t.IndexOf('\')
        if ($u -ge 0) { $inicio = $u } else { return $null }
    }

    $c = $t.Substring($inicio)

    # Corta o motivo que vem depois do caminho.
    $seta = $c.IndexOf(' => ')
    if ($seta -gt 0) { $c = $c.Substring(0, $seta) }

    # "C:\x\ UnauthorizedAccessException: Access to the path is denied."
    #
    # O nome da excecao vem depois do caminho, e atras dele vem a frase
    # inteira. Cortar so a ULTIMA palavra nao resolve: a ultima palavra e
    # "denied.". Entao corta na PRIMEIRA palavra que contenha "Exception" -
    # dali para a frente nada mais e caminho.
    $partes = $c.Split(' ')
    for ($i = 1; $i -lt $partes.Length; $i++) {
        if ($partes[$i].Contains('Exception')) {
            $partes = $partes[0..($i - 1)]
            break
        }
    }
    $c = ($partes -join ' ')

    $c = $c.TrimEnd(':', ' ')
    if ($c.Length -lt 3) { return $null }
    return $c
}

<#
    O caminho e do Windows, ou e dado do cartorio?

    Esta e a unica pergunta que separa ruido de problema, e por isso ela e
    explicita aqui em vez de ficar no julgamento de quem le o log.

    Do Windows: C:\Windows, os arquivos de memoria virtual, a lixeira, a
    pasta de restauracao do sistema. Nada disso se restaura de um backup de
    arquivos - numa reinstalacao o Windows e instalado do zero.

    Todo o resto e dado, ate prova em contrario. A pasta do sistema do
    cartorio dentro de Program Files conta como dado: varios sistemas
    guardam o banco de dados ali.
#>
function EhDoSistema([string]$caminho) {
    if (-not $caminho) { return $false }
    $c = $caminho.ToUpperInvariant()
    foreach ($p in @(
        ':\WINDOWS\', ':\WINDOWS"',
        'PAGEFILE.SYS', 'HIBERFIL.SYS', 'SWAPFILE.SYS',
        '\$RECYCLE.BIN', '\RECYCLER\',
        '\SYSTEM VOLUME INFORMATION',
        '\MSOCACHE\', '\$WINDOWS.~'
    )) {
        if ($c.Contains($p)) { return $true }
    }
    if ($c -match '^[A-Z]:\WINDOWS$') { return $true }
    return $false
}


# ==============================================================================

<#
    Acha em que porta o programa esta, e avisa se houver mais de um.

    O icone da bandeja sobe o servidor com a lista
    8200,8300,8400,8500,8600,8700,8800,8900,8989 e fica com a primeira livre.
    Procurar so na 8200 tem dois modos de errar:

      - o programa esta na 8300 (a 8200 estava ocupada quando ele subiu) e
        este script diria que nao ha programa nenhum;
      - ha DOIS rodando, e este script leria os avisos de um deles sem saber
        que existe outro fazendo o mesmo backup ao lado.
#>
$PORTAS_POSSIVEIS = @(8200, 8300, 8400, 8500, 8600, 8700, 8800, 8900, 8989)

function NoAr([int]$porta) {
    try { $c = New-Object Net.Sockets.TcpClient; $c.Connect('127.0.0.1', $porta); $c.Close(); return $true }
    catch { return $false }
}

Titulo 'Resumo dos avisos do backup'

$portasVivas = @($PORTAS_POSSIVEIS | Where-Object { NoAr $_ })

if ($portasVivas.Count -eq 0) {
    Erro 'o CH.Com Backup nao esta respondendo neste servidor.'
    Nota 'Abra o programa pelo icone ao lado do relogio e rode isto de novo.'
    Write-Host ""
    exit 1
}

# Se a porta normal responde, e nela que se fala. Senao, na que houver.
if ($portasVivas -contains $PortaDuplicati) { $porta = $PortaDuplicati }
else {
    $porta = $portasVivas[0]
    Aviso "o programa esta na porta $porta, e nao na $PortaDuplicati."
}

if ($portasVivas.Count -gt 1) {
    Aviso "ATENCAO: ha $($portasVivas.Count) programas rodando neste servidor."
    Nota  "portas respondendo: $($portasVivas -join ', ')"
    Nota  'Os dois fazem o mesmo backup e brigam pelo destino na nuvem.'
    Nota  'Reinicie este servidor e rode o DIAGNOSTICO.bat para conferir.'
    Nota  "O resumo abaixo e so do programa da porta $porta."
}

$base = "http://127.0.0.1:$porta"
<#
    Entra no programa. Ate tres tentativas, e diz o que REALMENTE aconteceu.

    Um try/catch que responde "senha recusada" para qualquer falha manda o
    tecnico atras da senha mesmo quando o problema e outro - versao antiga
    sem essa rota, o programa caindo no meio, a porta ocupada. O codigo HTTP
    e que decide: 401 e 403 sao senha, o resto nao e.
#>
function EntrarNoPrograma([string]$endereco) {
    for ($tentativa = 1; $tentativa -le 3; $tentativa++) {
        $senha = PedirSenha
        if (-not $senha) { Aviso 'cancelado.'; return $null }

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
                Erro 'senha recusada tres vezes.'
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

            Erro 'nao consegui entrar no programa.'
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
if (-not $login) { Write-Host ""; exit 1 }

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
    $forasDeCasa = @{}   # caminhos excluidos que NAO sao do Windows

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

                # Se este aviso significa "arquivo ficou de fora", guarda o
                # caminho - separando o que e do Windows do que nao e.
                if ($TIPOS_QUE_EXCLUEM -contains $tipo) {
                    $caminho = CaminhoDoAviso $texto
                    if ($caminho -and -not (EhDoSistema $caminho)) {
                        if (-not $forasDeCasa.ContainsKey($caminho)) {
                            $forasDeCasa[$caminho] = [PSCustomObject]@{ Tipo = $tipo; Vezes = 0 }
                        }
                        $forasDeCasa[$caminho].Vezes++
                    }
                }
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

    <#
        A parte que decide se o backup esta bom ou nao.

        Contagem por tipo diz o volume de ruido. Nao diz o que interessa: se
        algum ARQUIVO DO CARTORIO ficou de fora. E o mesmo aviso nos dois
        casos - o Duplicati escreve "Excluding path due to permission denied"
        tanto para um .etl do Windows quanto para a pasta do banco de dados
        do sistema do cartorio.

        Por isso o que aparece aqui e o CAMINHO, e so os que nao sao do
        Windows. Tudo que estiver nesta lista e dado que o backup NAO tem.
    #>
    if ($forasDeCasa.Count -gt 0) {
        Write-Host ""
        Write-Host "    ARQUIVOS QUE NAO ENTRARAM NO BACKUP" -ForegroundColor Red
        Write-Host "    (fora do Windows - estes precisam ser olhados)" -ForegroundColor Red
        Write-Host ""
        $lista = @($forasDeCasa.GetEnumerator() | Sort-Object { -$_.Value.Vezes })
        foreach ($item in ($lista | Select-Object -First 25)) {
            Write-Host ("    {0,5}x  " -f $item.Value.Vezes) -ForegroundColor Red -NoNewline
            Write-Host $item.Value.Tipo -ForegroundColor White -NoNewline
            Write-Host "  $($item.Key)" -ForegroundColor Gray
        }
        if ($lista.Count -gt 25) {
            Nota "... e mais $($lista.Count - 25) caminhos."
        }
    } else {
        $temExclusao = @($ordenado | Where-Object { $TIPOS_QUE_EXCLUEM -contains $_.Tipo })
        if ($temExclusao.Count -gt 0) {
            Write-Host ""
            Ok 'nenhum arquivo de fora do Windows ficou de fora do backup'
        }
    }
    # --- o que fazer --------------------------------------------------------
    $textoTudo = ($ordenado | ForEach-Object { $_.Tipo + ' ' + $_.Exemplo }) -join "`n"

    # Reconhece o caso pela ETIQUETA, nao pelo texto.
    #
    # O texto da mensagem e TRADUZIDO - num servidor em portugues sai "A opcao
    # fornecida ... nao e suportada". Procurar "is not supported" ali nao acha
    # nada, e o script diria que esta tudo bem num servidor cheio de problema.
    # A etiqueta entre colchetes ([...-UnsupportedOption]) nunca e traduzida.
    $opcaoInvalida = $textoTudo -match 'UnsupportedOption|-{3,}'
    $permissao     = $textoTudo -match 'PermissionDenied'
    $travado       = $textoTudo -match 'PathProcessingFailed|used by another process'
    $sumiu         = $textoTudo -match 'MissingFile|FileNotFound|DeletedFile'
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

