<#
================================================================================
  CH.Com Cofre - descobrir o que existe neste servidor

  Nada e assumido. O agente pergunta ao Windows o que ha aqui, e o resultado
  vira o plano de backup. Um cartorio pode ter host Hyper-V com 3 VMs, outro
  um servidor fisico com Firebird, outro os dois.

  Devolve um objeto com:
     EhHost          bool     Hyper-V presente e ligado
     EhServer        bool     Windows Server (importa: ver abaixo)
     VMs             lista    nome, ID, estado, tamanho, IntegrationServices
     Firebird        lista    instalacoes e bancos .fdb encontrados
     SqlServer       lista    instancias
     Discos          lista    espaco livre por unidade

  POR QUE "EhServer" IMPORTA

  O Hyper-V do Windows 11 funciona e faz production checkpoint - o checkpoint
  usa o VSS DENTRO da VM convidada, via Integration Services, e isso existe no
  Windows client tambem.

  O que NAO existe no client e o VSS Writer do Hyper-V no HOST. Ele so importa
  para quem faz backup do host inteiro pegando as VMs de fora. Como este agente
  exporta VM por VM com Export-VM, o caminho nao depende dele.

  Ainda assim o agente avisa, porque um cartorio nao deveria estar rodando
  producao em Windows client.
================================================================================
#>

function DescobrirAmbiente {
    $r = [PSCustomObject]@{
        Maquina    = $env:COMPUTERNAME
        Windows    = (Get-CimInstance Win32_OperatingSystem).Caption
        EhServer   = $false
        EhHost     = $false
        HyperVSemPermissao = $false
        HyperVNota = ''
        VMs        = @()
        Firebird   = @()
        SqlServer  = @()
        Discos     = @()
    }

    # ProductType: 1 = estacao de trabalho, 2 = controlador de dominio, 3 = servidor
    try {
        $r.EhServer = ((Get-CimInstance Win32_OperatingSystem).ProductType -ne 1)
    } catch { }

    $r.Discos = DescobrirDiscos
    $hv = DescobrirHyperV
    $r.EhHost = $hv.Ligado
    $r.HyperVNota = $hv.Nota
    $r.HyperVSemPermissao = $hv.SemPermissao
    $r.VMs = $hv.VMs
    $r.Firebird = DescobrirFirebird
    $r.SqlServer = DescobrirSqlServer

    return $r
}

<#
    Discos, com o TIPO de cada um.

    Nao basta saber quanto ha livre. A primeira versao escolheu a unidade com
    mais espaco livre e caiu num OneDrive de rede mapeado como Z: - exportar
    uma VM de 200 GB para la significaria empurrar 200 GB para a nuvem errada,
    devagar, e possivelmente estourar a conta do cliente.

    Area de trabalho do Cofre so pode ser DISCO LOCAL FIXO. Rede, pendrive e
    CD nao servem: rede porque o export e I/O pesado e a copia ja vai para a
    nuvem depois; removivel porque some.

    DriveType do Win32_LogicalDisk:
      2 = removivel   3 = fixo   4 = rede   5 = optico   6 = RAM
#>
function DescobrirDiscos {
    $tipos = @{}
    try {
        foreach ($ld in @(Get-CimInstance Win32_LogicalDisk -ErrorAction SilentlyContinue)) {
            $tipos[$ld.DeviceID.TrimEnd(':')] = [int]$ld.DriveType
        }
    } catch { }

    $lista = @()
    foreach ($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        if ($null -eq $d.Used -and $null -eq $d.Free) { continue }
        $livre = [long]$d.Free
        $total = [long]$d.Used + $livre
        if ($total -le 0) { continue }

        $tipo = if ($tipos.ContainsKey($d.Name)) { $tipos[$d.Name] } else { 0 }
        $nomeTipo = switch ($tipo) {
            2 { 'removivel' }
            3 { 'local' }
            4 { 'rede' }
            5 { 'optico' }
            6 { 'memoria' }
            default { 'desconhecido' }
        }

        $lista += [PSCustomObject]@{
            Unidade    = $d.Name
            LivreBytes = $livre
            TotalBytes = $total
            Tipo       = $nomeTipo
            ServeParaTrabalho = ($tipo -eq 3)
        }
    }
    return $lista
}

<#
    Hyper-V presente?

    Get-WindowsOptionalFeature exige elevacao e falha sem ela. Entao a
    deteccao usa duas coisas que qualquer usuario consegue ler:
      - o modulo Hyper-V do PowerShell existe?
      - o servico vmms esta rodando?

    O servico e o que decide: modulo instalado com servico parado significa
    Hyper-V presente mas desligado.
#>
function DescobrirHyperV {
    $res = [PSCustomObject]@{ Ligado = $false; SemPermissao = $false; Nota = ""; VMs = @() }

    $temModulo = [bool](Get-Module -ListAvailable -Name Hyper-V -ErrorAction SilentlyContinue)
    $svc = Get-Service -Name 'vmms' -ErrorAction SilentlyContinue

    if (-not $temModulo -and -not $svc) {
        $res.Nota = 'Hyper-V nao esta instalado nesta maquina.'
        return $res
    }
    if (-not $svc -or $svc.Status -ne 'Running') {
        $res.Nota = 'Hyper-V instalado, mas o servico de Gerenciamento de Maquina Virtual nao esta rodando.'
        return $res
    }
    if (-not $temModulo) {
        $res.Nota = 'O servico do Hyper-V roda, mas o modulo do PowerShell nao esta instalado. Falta o recurso "Modulo do Hyper-V para Windows PowerShell".'
        return $res
    }

    try { Import-Module Hyper-V -ErrorAction Stop } catch {
        $res.Nota = "nao consegui carregar o modulo Hyper-V: $($_.Exception.Message)"
        return $res
    }

    <#
        O Get-VM EXIGE PRIVILEGIO. E isso muda tudo.

        Descoberto com Hyper-V de verdade instalado: rodando como usuario
        comum, o Get-VM nao devolve lista vazia - ele LANCA "Voce nao tem a
        permissao necessaria para concluir esta tarefa".

        A primeira versao tratava qualquer falha como "sem VM", e o resultado
        seria a pior mentira que este sistema pode contar: a janela, que roda
        como usuario, diria "Hyper-V ligado, nenhuma maquina virtual" num host
        com tres VMs de cartorio rodando. O tecnico configuraria o Cofre
        achando que nao havia VM para proteger.

        Entao a falta de permissao vira um estado PROPRIO, com o conserto
        junto - e nunca "nao ha VM".
    #>
    try {
        $vms = @(Get-VM -ErrorAction Stop)
    } catch {
        $msg = $_.Exception.Message
        if ($msg -match 'permiss|permission|autoriza|authoriz') {
            $res.SemPermissao = $true
            $res.Nota = 'o Hyper-V esta ligado, mas este usuario nao tem permissao para ver as maquinas virtuais.'
        } else {
            $res.Nota = "nao consegui listar as maquinas virtuais: $msg"
        }
        return $res
    }

    $res.Ligado = $true

    foreach ($vm in $vms) {
        $bytes = 0
        foreach ($hd in @(Get-VMHardDiskDrive -VM $vm -ErrorAction SilentlyContinue)) {
            try {
                if ($hd.Path -and (Test-Path $hd.Path)) { $bytes += (Get-Item $hd.Path).Length }
            } catch { }
        }

        # Integration Services: sem o servico de VSS do convidado nao ha
        # production checkpoint, e o export cai para crash-consistent.
        $temVss = $false
        try {
            $ic = Get-VMIntegrationService -VM $vm -ErrorAction SilentlyContinue |
                  Where-Object { $_.Name -like '*VSS*' -or $_.Name -like '*Backup*' }
            $temVss = [bool]($ic | Where-Object { $_.Enabled })
        } catch { }

        $res.VMs += [PSCustomObject]@{
            Nome           = $vm.Name
            ID             = $vm.Id
            Estado         = [string]$vm.State
            TamanhoBytes   = $bytes
            MemoriaBytes   = [long]$vm.MemoryAssigned
            TipoCheckpoint = [string]$vm.CheckpointType
            VssNoConvidado = $temVss
        }
    }

    if ($res.VMs.Count -eq 0) {
        $res.Nota = 'Hyper-V ligado, mas nenhuma maquina virtual configurada.'
    }
    return $res
}

<#
    Firebird.

    Procurado com cuidado porque e o caso mais perigoso do parque: o Firebird
    NAO tem VSS Writer. Copiar um .fdb aberto produz um arquivo que as vezes
    abre e as vezes nao - e ninguem descobre qual dos dois ate precisar.

    A unica forma suportada pelo fabricante e o gbak. Por isso o agente
    localiza o gbak.exe, nao so o banco.
#>
function DescobrirFirebird {
    $achados = @()

    # 1. servico registrado - a pista mais confiavel do caminho da instalacao
    $pastas = @()
    try {
        foreach ($s in @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
                         Where-Object { $_.Name -like '*Firebird*' -or $_.DisplayName -like '*Firebird*' })) {
            if ($s.PathName) {
                $exe = $s.PathName.Trim('"').Split('"')[0]
                if (Test-Path $exe) { $pastas += Split-Path $exe -Parent }
            }
        }
    } catch { }

    # 2. lugares comuns
    foreach ($p in @(
        "$env:ProgramFiles\Firebird",
        "${env:ProgramFiles(x86)}\Firebird",
        'C:\Firebird'
    )) {
        if (Test-Path $p) {
            foreach ($sub in @(Get-ChildItem $p -Directory -ErrorAction SilentlyContinue)) {
                $pastas += $sub.FullName
            }
            $pastas += $p
        }
    }

    foreach ($pasta in ($pastas | Where-Object { $_ } | Select-Object -Unique)) {
        $gbak = CaminhoDe $pasta 'gbak.exe'
        if (-not (Test-Path $gbak)) {
            $gbak = CaminhoDe (CaminhoDe $pasta 'bin') 'gbak.exe'
        }
        if (Test-Path $gbak) {
            $versao = ''
            try { $versao = (Get-Item $gbak).VersionInfo.ProductVersion } catch { }
            $achados += [PSCustomObject]@{
                Pasta  = $pasta
                Gbak   = $gbak
                Versao = $versao
            }
        }
    }

    return $achados
}

<#
    SQL Server.

    Tem VSS Writer proprio, entao um backup de volume PODE sair consistente.
    Mesmo assim o agente faz o backup nativo, por dois motivos que o VSS nao
    resolve:

      - restaurar UMA base sem restaurar a maquina inteira
      - ponto no tempo, com os logs

    Descobre pelas instancias registradas, que e o unico jeito que funciona
    tanto para instancia padrao quanto para nomeada e para Express.
#>
function DescobrirSqlServer {
    $achados = @()
    try {
        foreach ($s in @(Get-Service -ErrorAction SilentlyContinue |
                         Where-Object { $_.Name -eq 'MSSQLSERVER' -or $_.Name -like 'MSSQL$*' })) {
            $instancia = if ($s.Name -eq 'MSSQLSERVER') { $env:COMPUTERNAME }
                         else { $env:COMPUTERNAME + '\' + $s.Name.Substring(6) }
            $achados += [PSCustomObject]@{
                Servico   = $s.Name
                Instancia = $instancia
                Estado    = [string]$s.Status
            }
        }
    } catch { }
    return $achados
}
