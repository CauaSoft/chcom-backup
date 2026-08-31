<#
================================================================================
  CH.Com Cofre - montar o pacote de instalacao

  Gera o .zip que vai para o servidor do cartorio.

  O que ele NAO deixa entrar:
    cofre.conf, rclone.conf, estado.json   sao daquele servidor, e o segundo
                                           carrega a chave de criptografia
    historico, registros                   idem
    arquivos de teste

  E ele CONFERE antes de fechar: um pacote com a chave de um cartorio dentro,
  entregue em outro, seria o pior defeito possivel deste projeto.
================================================================================
#>

[CmdletBinding()]
param(
    [string]$Raiz = 'C:\dev\chcom-cofre',
    [string]$Saida = 'C:\dev\chcom-cofre\dist'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $Raiz 'agente\modulos\comum.ps1')

Marca
Titulo 'Montando o pacote de instalacao'

# --- 1. auditar antes ---------------------------------------------------------
Passo 'auditando o projeto...'
$auditoria = & (Join-Path $Raiz 'verificar-cofre.ps1') -Raiz $Raiz
if ($LASTEXITCODE -gt 0) {
    Erro "a auditoria encontrou $LASTEXITCODE problema(s). O pacote nao foi montado."
    exit 1
}

# --- 2. montar ----------------------------------------------------------------
$nome = 'CH.Com-Cofre'
$pasta = CaminhoDe $Saida $nome
<#
    Limpar a pasta anterior.

    O CH.Com Cofre aberto SEGURA o chcom.ico - o WPF mantem o arquivo do
    icone da janela aberto enquanto ela existir. Tentar apagar devolve "o
    processo nao pode acessar o arquivo", que nao explica nada a quem esta
    montando o pacote.

    Entao a mensagem diz o que fazer. E existe uma correcao permanente do
    outro lado: as janelas agora carregam o icone com CacheOption = OnLoad,
    que le e solta. So que uma janela ABERTA ANTES dessa correcao continua
    segurando - e o aviso resolve esse caso tambem.
#>
if (Test-Path $pasta) {
    try {
        Remove-Item $pasta -Recurse -Force -ErrorAction Stop
    } catch {
        $abertos = @(Get-Process powershell, pwsh -ErrorAction SilentlyContinue |
                     Where-Object { $_.MainWindowTitle -like '*Cofre*' })
        Write-Host ''
        Erro 'nao consegui limpar a pasta anterior do pacote.'
        if ($abertos.Count -gt 0) {
            Nota 'O CH.Com Cofre esta ABERTO e segurando o arquivo do icone:'
            foreach ($p in $abertos) { Nota "  processo $($p.Id) - $($p.MainWindowTitle)" }
            Nota 'Feche a janela do Cofre e rode este script de novo.'
        } else {
            Nota $_.Exception.Message
        }
        Write-Host ''
        exit 1
    }
}
New-Item -ItemType Directory -Path $pasta -Force | Out-Null

# Ferramentas de laboratorio e arquivos deste servidor nao vao para o cartorio.
# criar-vm-de-teste.ps1 monta um cenario de teste - num servidor de producao
# ele so serviria para alguem criar VM sem querer.
$naoVai = @('cofre.conf', 'rclone.conf', 'estado.json', 'historico', 'registros',
            'testar-xaml.ps1', 'criar-vm-de-teste.ps1')

$origem = CaminhoDe $Raiz 'agente'
foreach ($item in @(Get-ChildItem $origem -Force)) {
    if ($item.Name -in $naoVai) { Nota "fora do pacote: $($item.Name)"; continue }
    Copy-Item $item.FullName -Destination $pasta -Recurse -Force
}

# o mesmo filtro dentro das subpastas
foreach ($n in $naoVai) {
    foreach ($achado in @(Get-ChildItem $pasta -Filter $n -Recurse -Force -ErrorAction SilentlyContinue)) {
        Remove-Item $achado.FullName -Recurse -Force
        Nota "removido do pacote: $($achado.Name)"
    }
}

$docs = CaminhoDe $pasta 'docs'
New-Item -ItemType Directory -Path $docs -Force | Out-Null
Copy-Item (CaminhoDe (CaminhoDe $Raiz 'docs') 'RESTAURAR-DO-COFRE.txt') $docs -Force

Ok "$(@(Get-ChildItem $pasta -Recurse -File).Count) arquivo(s) no pacote"

# --- 3. conferir que nao escapou segredo --------------------------------------
Titulo 'Conferindo o pacote'
$sensiveis = @(Get-ChildItem $pasta -Recurse -File -Force |
               Where-Object { $_.Name -in @('cofre.conf','rclone.conf','estado.json') })
if ($sensiveis.Count -gt 0) {
    foreach ($s in $sensiveis) { Erro "ARQUIVO SENSIVEL NO PACOTE: $($s.FullName)" }
    exit 1
}
Ok 'nenhum arquivo de configuracao ou chave no pacote'

$semRclone = -not (Test-Path (CaminhoDe $pasta 'rclone.exe'))
if ($semRclone) {
    Aviso 'o rclone nao esta no pacote - ele sera baixado na instalacao (precisa de internet)'
} else {
    Ok "rclone embutido ($([math]::Round((Get-Item (CaminhoDe $pasta 'rclone.exe')).Length/1MB,1)) MB) - instala sem internet"
}

$obrigatorios = @('INSTALAR.bat','LEIA-ME.txt','cofre.ps1','instalar-cofre.ps1',
                  'interface\cofre-ui.ps1','interface\assistente.ps1','marca\chcom.ico',
                  'docs\RESTAURAR-DO-COFRE.txt','LICENCA-RCLONE.txt')
$faltou = @($obrigatorios | Where-Object { -not (Test-Path (Join-Path $pasta $_)) })
if ($faltou.Count -gt 0) {
    foreach ($f in $faltou) { Erro "falta no pacote: $f" }
    exit 1
}
Ok "$($obrigatorios.Count) arquivo(s) essenciais conferidos"

# --- 4. fechar ----------------------------------------------------------------
<#
    DOIS PACOTES, E NAO UM.

    O do cartorio nao leva o INSTALAR-GERENTE.bat. Se levasse, bastaria um
    clique errado - ou um tecnico curioso - para um cartorio passar a enxergar
    a situacao dos outros 37 no mesmo bucket.

    O codigo e o MESMO nos dois. O que muda e uma linha no modo.txt, escrita
    pelo instalador. Manter dois codigos diferentes seria pior: a correcao
    feita num esqueceria do outro.
#>
Titulo 'Fechando os .zip'

$gerenteBat = CaminhoDe $pasta 'INSTALAR-GERENTE.bat'
if (-not (Test-Path $gerenteBat)) {
    Erro 'INSTALAR-GERENTE.bat nao esta no pacote - sem ele nao da para montar a versao do gerente'
    exit 1
}

# O do gerente primeiro, com tudo dentro.
$zipG = CaminhoDe $Saida "$nome-GERENTE.zip"
if (Test-Path $zipG) { Remove-Item $zipG -Force }
Compress-Archive -Path $pasta -DestinationPath $zipG -CompressionLevel Optimal
$mbG = [math]::Round((Get-Item $zipG).Length / 1MB, 1)
Ok "$nome-GERENTE.zip ($mbG MB) - so para o computador da CH.Com"

# Agora tira o instalador do gerente e fecha o do cartorio.
Remove-Item $gerenteBat -Force
$zip = CaminhoDe $Saida "$nome.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path $pasta -DestinationPath $zip -CompressionLevel Optimal
$mb = [math]::Round((Get-Item $zip).Length / 1MB, 1)
Ok "$nome.zip ($mb MB) - este vai para os cartorios"

# Conferido, e nao suposto: o pacote do cartorio nao pode ter como virar
# gerente.
$conferir = CaminhoDe $Saida '_conferindo'
if (Test-Path $conferir) { Remove-Item $conferir -Recurse -Force }
Expand-Archive -Path $zip -DestinationPath $conferir -Force
$vazou = @(Get-ChildItem $conferir -Recurse -Filter 'INSTALAR-GERENTE.bat' -Force)
Remove-Item $conferir -Recurse -Force
if ($vazou.Count -gt 0) {
    Erro 'o pacote do cartorio ficou com o INSTALAR-GERENTE.bat dentro'
    exit 1
}
Ok 'conferido: o pacote do cartorio nao tem como virar gerente'

Write-Host ''
Caixa @('PACOTES PRONTOS',
        '',
        "$nome.zip           ($mb MB)  -> cartorios",
        "$nome-GERENTE.zip   ($mbG MB)  -> so a CH.Com",
        '',
        'Descompacte no servidor e de dois cliques',
        'em INSTALAR.bat') 'Green'
Nota $zip
Write-Host ''
