<#
================================================================================
  CH.Com Cofre - o motor

  Roda sem interface, chamado pelo Agendador de Tarefas. Descobre o que ha
  neste servidor, decide o que proteger, protege, valida, cifra e envia.

  A cada passo escreve estado.json. E por ali que a janela sabe o que esta
  acontecendo - e por isso fechar a janela nao interrompe nada.

  USO
      cofre.ps1                  faz o que estiver na hora de fazer
      cofre.ps1 -Tudo            forca tudo agora, mensal e diario
      cofre.ps1 -SomenteBancos   so os bancos
      cofre.ps1 -Simular         mostra o plano e nao faz nada
================================================================================
#>

[CmdletBinding()]
param(
    [switch]$Tudo,
    [switch]$SomenteBancos,
    [switch]$Simular
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
foreach ($m in @('comum','descobrir','planejar','exportar-vm','imagem-servidor','bancos','pastas','validar','enviar')) {
    . (Join-Path $raiz "modulos\$m.ps1")

# Onde ficam configuracao, estado e historico. NAO e a pasta do codigo:
# Program Files e somente leitura para quem nao e administrador.
$dados = PastaDeDados $raiz
}

$ArquivoEstado = CaminhoDe $dados 'estado.json'
$ArquivoConfig = CaminhoDe $dados 'cofre.conf'
$PastaHistorico = CaminhoDe $dados 'historico'

# ------------------------------------------------------------------------------
#  Estado - o contrato com a interface
#
#  Escrito de forma atomica: grava num arquivo temporario e renomeia por cima.
#  Sem isso a janela pode ler o JSON no meio da escrita e receber texto
#  cortado - o que acontece raramente, e portanto no pior momento.
# ------------------------------------------------------------------------------
$script:Estado = [ordered]@{
    Versao      = 1
    Maquina     = $env:COMPUTERNAME
    Rodando     = $false
    Comecou     = $null
    Terminou    = $null
    EtapaAtual  = ''
    ItemAtual   = ''
    Progresso   = 0
    Resultado   = ''
    Itens       = 0
    Sucessos    = 0
    Falhas      = 0
    Detalhes    = @()
    Mensagem    = ''
}

function GravarEstado {
    try {
        $tmp = "$ArquivoEstado.tmp"
        $json = ($script:Estado | ConvertTo-Json -Depth 8)
        [System.IO.File]::WriteAllText($tmp, $json, [System.Text.UTF8Encoding]::new($false))
        Move-Item $tmp $ArquivoEstado -Force
    } catch { }
}

function Etapa([string]$etapa, [string]$item, [int]$progresso) {
    $script:Estado.EtapaAtual = $etapa
    $script:Estado.ItemAtual = $item
    if ($progresso -ge 0) { $script:Estado.Progresso = $progresso }
    GravarEstado
    Passo "$etapa $item"
}

function RegistrarItem($tipo, $nome, $sucesso, $detalhe, $bytes) {
    $script:Estado.Itens++
    if ($sucesso) { $script:Estado.Sucessos++ } else { $script:Estado.Falhas++ }
    $script:Estado.Detalhes += [ordered]@{
        Tipo = $tipo; Nome = $nome; Sucesso = $sucesso
        Detalhe = $detalhe; Bytes = $bytes
        Quando = (Get-Date).ToUniversalTime().ToString('o')
    }
    GravarEstado
}

# ------------------------------------------------------------------------------
#  Configuracao e agendamento
# ------------------------------------------------------------------------------
function LerConfig {
    if (-not (Test-Path $ArquivoConfig)) { return $null }
    try { return (Get-Content $ArquivoConfig -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

<#
    Esta tarefa esta na hora de rodar?

    Bancos sao pequenos e mudam todo dia: diario.
    VM e imagem sao grandes e o que se protege e o SERVIDOR, nao o trabalho do
    dia: mensal. Subir 200 GB toda noite pelo link de um cartorio do interior
    nao cabe, e nao acrescenta nada que o backup local ja nao cubra.

    O "ja passou" sai do historico, nao de um calendario fixo: se a maquina
    ficou desligada na data prevista, a tarefa roda na proxima vez que puder,
    em vez de pular o mes.
#>
function EstaNaHora($tarefa) {
    $ultima = UltimaVezQueRodou $tarefa.Tipo $tarefa.Nome
    if (-not $ultima) { return $true }

    $dias = ((Get-Date) - $ultima).TotalDays
    switch ($tarefa.Frequencia) {
        'diaria' { return ($dias -ge 1) }
        'mensal' { return ($dias -ge 30) }
        default  { return ($dias -ge 1) }
    }
}

function UltimaVezQueRodou([string]$tipo, [string]$nome) {
    if (-not (Test-Path $PastaHistorico)) { return $null }
    $maisRecente = $null
    foreach ($f in @(Get-ChildItem $PastaHistorico -Filter '*.json' -ErrorAction SilentlyContinue |
                     Sort-Object Name -Descending)) {
        try {
            $h = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($d in @($h.Detalhes)) {
                if ($d.Tipo -eq $tipo -and $d.Nome -eq $nome -and $d.Sucesso) {
                    $q = [datetime]$d.Quando
                    if (-not $maisRecente -or $q -gt $maisRecente) { $maisRecente = $q }
                }
            }
        } catch { }
        # Os arquivos vem do mais novo para o mais velho; achou, pode parar.
        if ($maisRecente) { break }
    }
    return $maisRecente
}

# ==============================================================================
#  Execucao
# ==============================================================================

DesligarCliqueQueTrava
IniciarRegistro (CaminhoDe $dados 'registros') 'cofre'

Marca
Titulo 'CH.Com Cofre - copia externa'

$config = LerConfig
$ambiente = DescobrirAmbiente
$plano = MontarPlano $ambiente $config

MostrarPlano $plano

if ($Simular) {
    Caixa @('SIMULACAO - nada foi feito') 'Cyan'
    exit 0
}

if (-not $config) {
    Erro 'este servidor ainda nao foi configurado.'
    Nota 'Abra o CH.Com Cofre e va em Configuracao, ou rode o CONFIGURAR.bat.'
    exit 1
}

# A area de trabalho vem da CONFIGURACAO, nunca e adivinhada na hora.
# Adivinhar ja custou caro aqui: uma versao escolheu a unidade com mais espaco
# livre e caiu num OneDrive de rede - exportar 200 GB de VM para la empurraria
# tudo para a nuvem errada e estouraria a conta do cliente.
$trabalho = $config.PastaDeTrabalho
if (-not $trabalho) {
    Erro 'nao ha area de trabalho configurada.'
    exit 1
}
if (-not (Test-Path $trabalho)) {
    try { New-Item -ItemType Directory -Path $trabalho -Force | Out-Null }
    catch { Erro "a area de trabalho nao existe e nao pude criar: $trabalho"; exit 1 }
}

$rclone = CaminhoDoRclone $raiz
if (-not $rclone) {
    Erro 'o rclone nao esta nesta pasta. Rode o INSTALAR.bat de novo, por cima.'
    exit 1
}
$rcloneConf = CaminhoDe $dados 'rclone.conf'

$carimbo = Get-Date -Format 'yyyy-MM-dd'

$script:Estado.Rodando = $true
$script:Estado.Comecou = (Get-Date).ToUniversalTime().ToString('o')
$script:Estado.Resultado = 'em andamento'
GravarEstado

$tarefas = @($plano.Tarefas)
if ($SomenteBancos) {
    $tarefas = @($tarefas | Where-Object { $_.Tipo -in @('firebird','sqlserver') })
} elseif (-not $Tudo) {
    $tarefas = @($tarefas | Where-Object { EstaNaHora $_ })
}

if ($tarefas.Count -eq 0) {
    Ok 'nada a fazer agora - tudo dentro do prazo'
    $script:Estado.Rodando = $false
    $script:Estado.Resultado = 'nada a fazer'
    $script:Estado.Terminou = (Get-Date).ToUniversalTime().ToString('o')
    GravarEstado
    exit 0
}

Titulo "Vai executar $($tarefas.Count) tarefa(s)"

$i = 0
foreach ($t in $tarefas) {
    $i++
    $pct = [int](($i - 1) / $tarefas.Count * 100)
    $pastaItem = $null
    $ok = $false
    $detalhe = ''
    $bytes = 0

    try {
        switch ($t.Tipo) {

            'vm' {
                Etapa 'exportando maquina virtual' $t.Nome $pct
                $ex = ExportarVM -VM $t.Alvo -PastaDestino (CaminhoDe $trabalho 'vm')
                if (-not $ex.Sucesso) { throw $ex.Erro }
                $pastaItem = $ex.Pasta
                $bytes = $ex.TamanhoBytes
                $detalhe = $ex.Consistencia

                Etapa 'conferindo se o export importa' $t.Nome $pct
                $v = ValidarExportDeVM $pastaItem
                if (-not $v.Importavel) { throw "o export nao e importavel: $($v.Erro)" }
                foreach ($rr in $v.Ressalvas) { Aviso "ressalva: $rr" }
                $ok = $true
            }

            'imagem' {
                Etapa 'gerando imagem do servidor' $t.Nome $pct
                $im = ImagemDoServidor -Destino $trabalho
                if (-not $im.Sucesso) { throw $im.Erro }
                $pastaItem = $im.Pasta
                $bytes = $im.TamanhoBytes

                Etapa 'conferindo a imagem' $t.Nome $pct
                $c = ConferirImagem $pastaItem
                if (-not $c.Integra) { throw "a imagem nao passou na conferencia: $($c.Erro)" }
                $detalhe = "$($c.Discos) disco(s)"
                foreach ($rr in $c.Ressalvas) { Aviso "ressalva: $rr" }
                $ok = $true
            }

            'pasta' {
                Etapa 'copiando pasta' $t.Nome $pct
                # Uma subpasta por pasta configurada, com o nome achatado:
                # "Z:\DADOS\Escrituras" vira "Z_DADOS_Escrituras". Sem isso,
                # duas pastas com o mesmo nome final se sobrescreveriam.
                $apelido = ($t.Alvo -replace '[:\/]', '_').Trim('_')
                $pastaItem = CaminhoDe (CaminhoDe $trabalho 'pastas') $apelido
                $cp = CopiarPasta -Origem $t.Alvo -Destino $pastaItem
                if (-not $cp.Sucesso) { throw $cp.Erro }
                $bytes = $cp.TamanhoBytes

                $detalhe = if ($cp.UsouSombra) { 'copia de sombra' } else { 'SEM copia de sombra' }
                if ($cp.NaoCopiados -gt 0) {
                    # Arquivo que ficou de fora vira AVISO no relatorio, e nao
                    # some no meio de um numero. Foi o defeito central do
                    # sistema anterior: backup verde com dado faltando.
                    Aviso "$($t.Nome): $($cp.NaoCopiados) arquivo(s) NAO copiados"
                    Nota $cp.Aviso
                    $detalhe += " - $($cp.NaoCopiados) arquivo(s) de fora"
                }
                $ok = $true
            }

            'firebird' {
                Etapa 'backup do Firebird' $t.Nome $pct
                $pastaItem = CaminhoDe $trabalho 'firebird'
                $arq = CaminhoDe $pastaItem ('banco-' + $carimbo + '.fbk')
                $fb = BackupFirebird -Gbak $t.Alvo.Gbak -Banco $config.BancoFirebird -Destino $arq
                if (-not $fb.Sucesso) { throw $fb.Erro }
                $bytes = $fb.TamanhoBytes

                Etapa 'conferindo se o .fbk restaura' $t.Nome $pct
                $cf = ConferirFirebird -Gbak $t.Alvo.Gbak -Arquivo $arq
                if (-not $cf.Restaura) { throw "o .fbk nao restaurou no teste: $($cf.Erro)" }
                $detalhe = 'gbak conferido por restauracao de teste'
                $ok = $true
            }

            'sqlserver' {
                Etapa 'backup do SQL Server' $t.Nome $pct
                $pastaItem = CaminhoDe $trabalho 'sqlserver'
                $sq = BackupSqlServer -Instancia $t.Alvo.Instancia -PastaDestino $pastaItem
                if (-not $sq.Sucesso) { throw $sq.Erro }
                $bytes = $sq.TamanhoBytes
                $detalhe = "$($sq.Bases.Count) base(s), todas com RESTORE VERIFYONLY"
                $ok = $true
            }
        }

        if ($ok -and $pastaItem) {
            Etapa 'calculando impressoes digitais' $t.Nome $pct
            $manifesto = CaminhoDe $pastaItem 'cofre-manifesto.json'
            GerarManifesto -Pasta $pastaItem -ArquivoManifesto $manifesto `
                -Extra @{ Item = $t.Nome; Tipo = $t.Tipo; Consistencia = $detalhe } | Out-Null

            Etapa 'cifrando e enviando' $t.Nome $pct
            <#
                O caminho no destino segue a estrutura da CH.Com:

                    backup-aws-ch/<CARTORIO>/<SERVIDOR>/<DISCO>/<AAAA-MM-DD>

                O <DISCO> sai da ORIGEM de verdade - a letra da unidade que a
                pessoa escolheu na tela - e nao de um rotulo generico. Antes
                ele nem existia no caminho: a origem "E:\DADOS" virava um
                apelido achatado no nome de uma pasta local, e o disco se
                perdia antes de chegar na AWS.

                O nome do item vai DENTRO da pasta da data, e nao como um
                nivel proprio: assim tres VMs enviadas no mesmo dia ficam
                lado a lado sob a mesma data, que e como se procura por elas.
            #>
            $disco = DiscoDaOrigem $t.Tipo ([string]$t.Alvo)
            $destino = CaminhoNoDestino -Remoto $config.Remoto `
                -Cartorio (NomeParaDestino $config.Cartorio) `
                -Servidor (NomeParaDestino $ambiente.Maquina) `
                -Disco $disco `
                -Data $carimbo
            $destino = $destino + '/' + (NomeParaDestino $t.Nome)
            $envio = EnviarPasta -Rclone $rclone -Config $rcloneConf `
                       -Origem $pastaItem -DestinoRemoto $destino
            if (-not $envio.Sucesso) { throw "o envio falhou: $($envio.Erro)" }

            Etapa 'conferindo o que chegou na AWS' $t.Nome $pct
            $cc = ConferirEnvio -Rclone $rclone -Config $rcloneConf `
                    -DestinoRemoto $destino -BytesEsperados $envio.BytesEnviados
            if (-not $cc.Confere) { throw "o destino nao confere: $($cc.Erro)" }

            Ok "$($t.Nome): $(Tamanho $bytes) enviados e conferidos"
        }

    } catch {
        $ok = $false
        $detalhe = $_.Exception.Message
        Erro "$($t.Nome): $detalhe"
    } finally {
        # A area de trabalho e limpa SEMPRE, inclusive quando falha. Um export
        # de 200 GB deixado para tras enche o disco e a proxima rodada nem
        # comeca - e o cartorio fica sem copia externa por causa de espaco.
        if ($pastaItem -and (Test-Path $pastaItem) -and -not $config.ManterCopiaLocal) {
            Etapa 'limpando a area de trabalho' $t.Nome $pct
            Remove-Item $pastaItem -Recurse -Force -ErrorAction SilentlyContinue
        }
        RegistrarItem $t.Tipo $t.Nome $ok $detalhe $bytes
    }
}

# --- fim ----------------------------------------------------------------------
$script:Estado.Rodando = $false
$script:Estado.Progresso = 100
$script:Estado.Terminou = (Get-Date).ToUniversalTime().ToString('o')
$script:Estado.Resultado = if ($script:Estado.Falhas -eq 0) { 'sucesso' }
                           elseif ($script:Estado.Sucessos -gt 0) { 'parcial' }
                           else { 'falhou' }
GravarEstado

# Uma copia do estado por execucao. E daqui que sai a tela de historico e a
# resposta para "ha quanto tempo esta VM nao sobe".
try {
    if (-not (Test-Path $PastaHistorico)) { New-Item -ItemType Directory -Path $PastaHistorico -Force | Out-Null }
    Copy-Item $ArquivoEstado (CaminhoDe $PastaHistorico ((Get-Date -Format 'yyyy-MM-dd_HHmmss') + '.json')) -Force
} catch { }

<#
    Publica o estado no bucket, para o programa do gerente ler.

    E a ultima etapa, e a menos importante das que existem: se falhar aqui, o
    backup ja esta feito, conferido e na AWS. Um erro de publicacao nao pode
    transformar uma execucao bem sucedida em falha - por isso vira aviso, e
    nao excecao.

    Substitui o painel-servidor: em vez de o cartorio empurrar um relatorio
    para uma maquina exposta na internet, ele deixa o estado ao lado do
    proprio backup, e quem tem a credencial de leitura busca.
#>
try {
    Etapa 'publicando o estado no Cofre' '' 100
    $pub = PublicarEstado -Rclone $rclone -Config $rcloneConf `
        -Bucket $config.Bucket `
        -Cartorio (NomeParaDestino $config.Cartorio) `
        -Servidor (NomeParaDestino $ambiente.Maquina) `
        -ArquivoEstado $ArquivoEstado

    if ($pub.Publicado) { Ok "estado publicado em $($pub.Destino)" }
    else { Aviso "nao consegui publicar o estado: $($pub.Erro)" }
} catch {
    Aviso "nao consegui publicar o estado: $($_.Exception.Message)"
}

Write-Host ''
if ($script:Estado.Falhas -eq 0) {
    Caixa @('COPIA EXTERNA CONCLUIDA E CONFERIDA',
            '',
            "$($script:Estado.Sucessos) item(ns) enviados para a AWS.") 'Green'
} else {
    Caixa @("$($script:Estado.Falhas) ITEM(NS) FALHARAM",
            '',
            "$($script:Estado.Sucessos) enviado(s), $($script:Estado.Falhas) com problema.") 'Red'
}
Write-Host ''
