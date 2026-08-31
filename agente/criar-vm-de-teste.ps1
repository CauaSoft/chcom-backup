<#
================================================================================
  CH.Com Cofre - criar uma VM de teste

  NAO E PARTE DO PRODUTO. E uma ferramenta de laboratorio, para montar num
  computador de testes o cenario que existe no cartorio - host Hyper-V com
  maquina virtual ligada - e assim exercitar o Export-VM de verdade.

  Nao vai no pacote que vai para o cliente.

  O QUE ELE FAZ

  1. confere que o Hyper-V esta instalado e no ar
  2. confere que ha um switch de rede utilizavel
  3. cria a VM de geracao 2, com disco dinamico
  4. deixa pronta para receber um sistema

  POR QUE GERACAO 2

  Geracao 1 usa BIOS antigo e IDE; geracao 2 usa UEFI e SCSI, que e o que os
  servidores de cartorio usam de verdade. Testar em geracao 1 provaria o
  export num cenario que nao existe no parque.
================================================================================
#>

[CmdletBinding()]
param(
    [string]$Nome = 'TESTE-COFRE',
    [int]$MemoriaGB = 4,
    [int]$DiscoGB = 40,
    [string]$Pasta = 'C:\VMs'
)

$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $raiz 'modulos\comum.ps1')

DesligarCliqueQueTrava
Marca
Titulo 'Criar VM de teste'

if (-not (EhAdministrador)) {
    Erro 'precisa ser executado como Administrador.'
    exit 1
}

# --- 1. Hyper-V esta de pe? ---------------------------------------------------
if (-not (Get-Module -ListAvailable -Name Hyper-V)) {
    Erro 'o modulo Hyper-V do PowerShell nao esta instalado.'
    Nota 'Rode como Administrador e REINICIE:'
    Nota '  Enable-WindowsOptionalFeature -Online -All -FeatureName Microsoft-Hyper-V'
    exit 1
}
Import-Module Hyper-V -ErrorAction Stop

$svc = Get-Service vmms -ErrorAction SilentlyContinue
if (-not $svc -or $svc.Status -ne 'Running') {
    Erro 'o servico do Hyper-V nao esta rodando.'
    Nota 'Se voce acabou de instalar o Hyper-V, REINICIE o computador.'
    exit 1
}
Ok 'Hyper-V no ar'

# --- 2. rede ------------------------------------------------------------------
# Sem switch a VM sobe sem rede - e um Windows sem rede nao ativa os Servicos
# de Integracao direito, que e justamente o que se quer testar.
$switch = @(Get-VMSwitch -ErrorAction SilentlyContinue | Select-Object -First 1)
if ($switch.Count -eq 0) {
    Aviso 'nao ha switch de rede no Hyper-V.'
    Passo 'criando um switch interno...'
    try {
        New-VMSwitch -Name 'CH.Com Teste' -SwitchType Internal -ErrorAction Stop | Out-Null
        $switch = @(Get-VMSwitch -Name 'CH.Com Teste')
        Ok 'switch interno criado'
    } catch {
        Aviso "nao consegui criar o switch: $($_.Exception.Message)"
    }
}
if ($switch.Count -gt 0) { Ok "rede: $($switch[0].Name)" }

# --- 3. a VM ------------------------------------------------------------------
if (Get-VM -Name $Nome -ErrorAction SilentlyContinue) {
    Aviso "ja existe uma VM chamada $Nome."
    Nota 'Para recriar, apague antes no Gerenciador do Hyper-V.'
    exit 1
}

if (-not (Test-Path $Pasta)) { New-Item -ItemType Directory -Path $Pasta -Force | Out-Null }
$vhd = CaminhoDe $Pasta "$Nome.vhdx"

Passo "criando $Nome ($MemoriaGB GB de memoria, disco de ate $DiscoGB GB)"
$parametros = @{
    Name               = $Nome
    Generation         = 2
    MemoryStartupBytes = ($MemoriaGB * 1GB)
    NewVHDPath         = $vhd
    NewVHDSizeBytes    = ($DiscoGB * 1GB)
}
if ($switch.Count -gt 0) { $parametros['SwitchName'] = $switch[0].Name }

New-VM @parametros | Out-Null

# Memoria dinamica: o host tem 16 GB e precisa continuar utilizavel. Fixar 4 GB
# tira 4 GB do host mesmo com a VM ociosa.
Set-VMMemory -VMName $Nome -DynamicMemoryEnabled $true `
    -MinimumBytes 1GB -StartupBytes ($MemoriaGB * 1GB) -MaximumBytes ($MemoriaGB * 1GB)

Set-VMProcessor -VMName $Nome -Count 2

# Production checkpoint com queda para standard: e o padrao do Windows e o
# que o Export-VM usa. Sem isso o export nao sai application-consistent.
Set-VM -Name $Nome -CheckpointType ProductionOnly -AutomaticCheckpointsEnabled $false

Ok "VM $Nome criada"
Nota "disco: $vhd"

Write-Host ''
Caixa @('VM DE TESTE CRIADA',
        '',
        "Falta instalar um sistema dentro dela.",
        '',
        'Abra o Gerenciador do Hyper-V, ligue a VM e instale',
        'um Windows a partir de um ISO - ou use a Criacao Rapida',
        'com o "Windows 11 dev environment", que ja vem pronto.') 'Green'

Nota 'Depois que o sistema estiver instalado, confira:'
Nota "  Get-VMIntegrationService -VMName $Nome | Select Name, Enabled"
Nota 'O que importa e o "Backup (volume shadow copy)" com Enabled = True.'
Write-Host ''
