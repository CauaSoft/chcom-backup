<#
================================================================================
  CH.Com Cofre - decidir sozinho o que proteger

  O AGENTE NAO PERGUNTA O QUE FAZER. ELE OLHA E DECIDE.

  Sao mais de 50 cartorios, e nenhum e igual ao outro: uns tem host Hyper-V
  com 3 VMs, outros um servidor fisico com Firebird, outros um servidor fisico
  com SQL Server e mais nada. Configurar cada um a mao e onde o erro entra -
  e o erro so aparece no dia do desastre.

  Entao a regra e: o agente descobre o ambiente e monta o plano. Se ele nao
  souber proteger alguma coisa, ele DIZ, em vez de fingir que protegeu.

  AS DECISOES, E O PORQUE DE CADA UMA

  Host Hyper-V com VMs
      Export-VM por VM, com production checkpoint.
      Uma VM por vez, cada uma independente da outra.

  Servidor fisico (sem Hyper-V), Windows Server
      wbadmin -allCritical. Gera VHDX dos volumes criticos e permite
      recuperacao bare metal pelo ambiente de recuperacao do Windows.
      O mesmo VHDX tambem pode ser anexado a uma VM para subir o servidor
      em outro lugar enquanto o hardware nao volta.

  Servidor fisico, Windows client
      O wbadmin do Windows client e limitado e a Microsoft ja o marcou como
      obsoleto. O agente AVISA que nao ha imagem de sistema confiavel aqui e
      protege dados e bancos - dizendo com todas as letras que a maquina
      inteira nao volta sozinha.

  Bancos, sempre
      Firebird: gbak. Nao existe outra forma suportada.
      SQL Server: BACKUP DATABASE, mesmo havendo imagem - porque imagem nao
      restaura UMA base nem ponto no tempo.

  Bancos DENTRO de VMs
      O host nao alcanca. O agente detecta que ha VMs e avisa que o Cofre
      precisa ser instalado tambem dentro delas. Nao ha como um backup do
      host garantir o gbak de um Firebird que roda na VM.
================================================================================
#>

function MontarPlano {
    param(
        [Parameter(Mandatory)] $Ambiente,
        # As pastas escolhidas a mao vem da configuracao, e nao da deteccao:
        # nao ha como o agente adivinhar qual pasta do servidor guarda o que
        # importa para aquele cartorio.
        $Config = $null
    )

    $plano = [PSCustomObject]@{
        Estrategia   = ''
        Tarefas      = @()
        Avisos       = @()
        NaoProtegido = @()
        PorDecisao   = @()   # fora de escopo de proposito - NAO e falha
    }

    <#
        Hyper-V ligado, mas sem permissao para enxergar as VMs.

        Nao e o mesmo que "nao ha VM", e a diferenca e a mais perigosa deste
        sistema: um host com tres VMs de cartorio apareceria como "nada a
        proteger", e o Cofre seria configurado sem elas. O backup existiria,
        ficaria verde, e nao teria nenhuma maquina virtual dentro.

        Por isso vira NAO PROTEGIDO com o conserto junto, e nao um silencio.
    #>
    if ($Ambiente.EhHost -eq $false -and $Ambiente.HyperVSemPermissao) {
        $plano.NaoProtegido += ('este usuario nao tem permissao para ver as maquinas virtuais. ' +
            'Rode o CH.Com Cofre como Administrador, ou acrescente o usuario ao grupo ' +
            '"Administradores do Hyper-V" do Windows.')
    }

    # --- 1. maquinas virtuais ---
    # --- 1. maquinas virtuais -------------------------------------------------
    if ($Ambiente.EhHost -and $Ambiente.VMs.Count -gt 0) {
        $plano.Estrategia = 'host Hyper-V'

        foreach ($vm in $Ambiente.VMs) {
            # A consistencia e decidida AQUI e mostrada no plano, antes de
            # rodar. Uma VM sem o servico de backup do convidado sai
            # crash-consistent - equivalente a puxar o cabo de energia. Costuma
            # restaurar, mas nao ha promessa, e quem opera precisa saber disso
            # ANTES, nao no dia em que o cartorio parar.
            if ($vm.Estado -ne 'Running') {
                $comoFica = 'VM desligada - copia integra'
            } elseif ($vm.VssNoConvidado) {
                $comoFica = 'Export-VM com production checkpoint (application-consistent)'
            } else {
                $comoFica = 'SEM production checkpoint - vai sair CRASH-CONSISTENT'
                $plano.Avisos += "VM $($vm.Nome): sem o servico de backup nos Servicos de Integracao. O backup dela sai crash-consistent. Instale/ligue os Servicos de Integracao DENTRO da VM."
            }

            $plano.Tarefas += [PSCustomObject]@{
                Tipo       = 'vm'
                Nome       = $vm.Nome
                Alvo       = $vm
                Frequencia = 'mensal'
                Porque     = $comoFica
            }
        }

        $plano.Avisos += 'Bancos que rodam DENTRO das VMs nao sao alcancados daqui. Instale o Cofre dentro de cada VM que tenha banco.'
    }

    # --- 2. a propria maquina -------------------------------------------------
    $imagem = DecidirImagemDoSistema $Ambiente
    if ($imagem.Possivel) {
        if (-not $plano.Estrategia) { $plano.Estrategia = 'servidor fisico' }
        $plano.Tarefas += [PSCustomObject]@{
            Tipo       = 'imagem'
            Nome       = $(if ($Ambiente.EhHost) { "Host $($Ambiente.Maquina) (sistema e configuracao do Hyper-V)" } else { $Ambiente.Maquina })
            Alvo       = $imagem
            Frequencia = 'mensal'
            Porque     = $imagem.Porque
        }
    } else {
        if (-not $plano.Estrategia) { $plano.Estrategia = 'somente dados e bancos' }

        # Nem toda coisa fora do backup e um problema.
        #
        # Num host Hyper-V, nao subir o host inteiro e DECISAO: o que vale sao
        # as VMs, e o host se reinstala em duas horas. Marcar isso em vermelho
        # como "NAO PROTEGIDO" faria o tecnico achar que algo quebrou, e
        # vermelho que nao significa problema treina todo mundo a ignorar
        # vermelho.
        #
        # Ja um Windows client sem imagem de sistema E um problema de verdade:
        # aquela maquina nao volta sozinha, e alguem precisa saber disso antes
        # do desastre, nao depois.
        if ($imagem.EhDecisao) {
            $plano.PorDecisao += "a maquina inteira nao sobe: $($imagem.Porque)"
        } else {
            $plano.NaoProtegido += "a maquina inteira: $($imagem.Porque)"
        }
    }

    # --- 3. discos inteiros escolhidos na interface ---------------------------
    #
    # Um disco marcado vira uma tarefa de pasta com a raiz do volume. E a
    # mesma copia de sombra: nao ha diferenca tecnica entre copiar "D:\" e
    # copiar "D:\DADOS" - a diferenca esta em quanto tempo leva, e isso a
    # interface ja mostrou antes de a pessoa marcar.
    if ($Config -and $Config.Discos) {
        foreach ($d in @($Config.Discos)) {
            if (-not $d) { continue }
            $raizDisco = $d + ':\'
            if (-not (Test-Path $raizDisco)) {
                $plano.NaoProtegido += "o disco configurado nao esta mais presente: $raizDisco"
                continue
            }
            $plano.Tarefas += [PSCustomObject]@{
                Tipo       = 'pasta'
                Nome       = "Disco $d`: (inteiro)"
                Alvo       = $raizDisco
                Frequencia = 'diaria'
                Porque     = 'disco inteiro, com copia de sombra do Windows'
            }
        }
        if (-not $plano.Estrategia) { $plano.Estrategia = 'discos e bancos' }
    }

    # --- 4. pastas escolhidas a mao -------------------------------------------
    #
    # Nem todo dado de cartorio esta dentro de VM ou de banco: ha a pasta dos
    # digitalizados, a dos anexos do sistema, a compartilhada onde o pessoal
    # trabalha. Isso nao da para detectar - so o tecnico sabe qual pasta
    # importa - entao vem da configuracao.
    if ($Config -and $Config.Pastas) {
        foreach ($p in @($Config.Pastas)) {
            if (-not $p) { continue }
            $existe = Test-Path $p
            if (-not $existe) {
                $plano.NaoProtegido += "a pasta configurada nao existe mais: $p"
                continue
            }
            $plano.Tarefas += [PSCustomObject]@{
                Tipo       = 'pasta'
                Nome       = $p
                Alvo       = $p
                Frequencia = 'diaria'
                Porque     = 'copia de sombra do Windows (le arquivo aberto)'
            }
        }
        if (-not $plano.Estrategia) { $plano.Estrategia = 'pastas e bancos' }
    }

    # --- 5. bancos ------
    foreach ($fb in $Ambiente.Firebird) {
        $plano.Tarefas += [PSCustomObject]@{
            Tipo       = 'firebird'
            Nome       = "Firebird em $($fb.Pasta)"
            Alvo       = $fb
            Frequencia = 'diaria'
            Porque     = 'gbak - copiar o .fdb aberto nao e backup valido'
        }
    }

    foreach ($sql in $Ambiente.SqlServer) {
        if ($sql.Estado -ne 'Running') {
            $plano.Avisos += "SQL Server $($sql.Instancia) esta parado - nao da para fazer backup nativo."
            continue
        }
        $plano.Tarefas += [PSCustomObject]@{
            Tipo       = 'sqlserver'
            Nome       = $sql.Instancia
            Alvo       = $sql
            Frequencia = 'diaria'
            Porque     = 'BACKUP DATABASE - permite restaurar UMA base, o que imagem nao permite'
        }
    }

    # --- 6. o agente nao achou nada para proteger -----------------------------
    if ($plano.Tarefas.Count -eq 0) {
        $plano.NaoProtegido += 'nada foi identificado para proteger nesta maquina'
    }

    return $plano
}

<#
    Da para tirar imagem do sistema desta maquina?

    Tres respostas possiveis, e as tres importam:

    SIM, com wbadmin do Windows Server
        O recurso "Windows Server Backup" existe e o comando responde.
        wbadmin start backup -allCritical grava VHDX dos volumes criticos,
        e wbadmin start sysrecovery restaura a maquina do zero pelo ambiente
        de recuperacao. E o unico caminho nativo, gratuito e suportado para
        bare metal em Windows Server.

    NAO, e um host Hyper-V
        Nao e defeito: num host, o que interessa sao as VMs. O host em si e
        Windows + funcao Hyper-V, que se reinstala em duas horas. Gastar
        banda subindo o host inteiro todo mes nao se paga.

    NAO, e Windows client
        O wbadmin existe no Windows 10 e 11, mas o recurso de imagem foi
        marcado como obsoleto pela Microsoft e nao recebe correcao. Confiar
        nele para recuperar um servidor de cartorio seria irresponsavel.
        O agente diz isso em voz alta e protege dados e bancos.
#>
<#
    Da para tirar imagem do sistema desta maquina?

    O HOST HYPER-V TAMBEM ENTRA. Isso mudou depois de pensar melhor.

    A primeira versao deixava o host de fora "de proposito", com o argumento
    de que o que vale sao as VMs e que o host se reinstala em duas horas.
    Estava errado, e por dois motivos concretos:

      1. "Reinstalar em duas horas" e otimismo. Instalar Windows Server,
         acrescentar a funcao Hyper-V, refazer os switches virtuais com os
         mesmos nomes - se o nome do switch mudar, TODA VM importada sobe sem
         rede - reconfigurar RAID, drivers e licenca. Num dia de desastre,
         isso e um dia inteiro.

      2. A imagem do host e BARATA. O wbadmin -allCritical pega so os volumes
         criticos: o sistema e o boot. Os discos onde moram os .vhdx ficam de
         fora, e sao eles que pesam. Na pratica sao 40 a 80 GB por host, uma
         vez por mes - perto de centenas de GB de VM, e ruido.

    Entao: host = imagem dos volumes criticos, VMs = export individual. As
    duas coisas, e nao uma ou outra.

    QUANDO AINDA NAO DA

    Windows client. O recurso de imagem do Windows 10 e 11 foi marcado como
    obsoleto pela Microsoft e nao recebe correcao. Confiar nele para recuperar
    um servidor de cartorio seria irresponsavel - o agente diz isso em voz
    alta em vez de fingir que protegeu.
#>
function DecidirImagemDoSistema {
    param([Parameter(Mandatory)] $Ambiente)

    $r = [PSCustomObject]@{
        Possivel = $false
        EhDecisao = $false
        Ferramenta = ''
        Porque = ''
        Volumes = @()
    }

    if (-not $Ambiente.EhServer) {
        <#
            Windows client: da para fazer, nao da para restaurar.

            Isto foi CONFERIDO, e nao suposto. O wbadmin.exe existe no
            Windows 11 e aceita START BACKUP. Mas a lista de comandos dele e:

                ENABLE BACKUP, DISABLE BACKUP, START BACKUP, STOP JOB,
                GET VERSIONS, GET ITEMS, GET STATUS, DELETE BACKUP

            Falta o START SYSRECOVERY - o comando que recupera a maquina
            inteira pelo ambiente de recuperacao do Windows. Ele existe so na
            edicao Server.

            Ou seja: a imagem ate seria gerada, e ficaria verde no painel.
            So que no dia do desastre nao haveria com o que restaurar. Backup
            que nao restaura nao e backup - e por isso isto e NAO PROTEGIDO,
            e nao um aviso.
        #>
        $r.Porque = 'Windows client faz o backup mas NAO RESTAURA a maquina: o wbadmin daqui nao tem o comando START SYSRECOVERY'
        return $r
    }

    $wb = $null
    try { $wb = (Get-Command wbadmin.exe -ErrorAction Stop).Source } catch { }
    if (-not $wb) {
        $r.Porque = 'o comando wbadmin nao existe nesta maquina'
        return $r
    }

    $temRecurso = $false
    try {
        $f = Get-WindowsFeature -Name 'Windows-Server-Backup' -ErrorAction Stop
        $temRecurso = ($f.InstallState -eq 'Installed')
    } catch {
        # Get-WindowsFeature so existe em Server. Se falhou, tenta pelo servico.
        $temRecurso = [bool](Get-Service -Name 'wbengine' -ErrorAction SilentlyContinue)
    }

    if (-not $temRecurso) {
        $r.Porque = 'o recurso Windows Server Backup nao esta instalado. Instale com: Install-WindowsFeature Windows-Server-Backup'
        return $r
    }

    $r.Possivel = $true
    $r.Ferramenta = $wb
    $r.Porque = if ($Ambiente.EhHost) {
        'wbadmin -allCritical: o host, com a configuracao do Hyper-V e os switches virtuais'
    } else {
        'wbadmin -allCritical: gera VHDX dos volumes criticos e permite recuperacao bare metal'
    }
    return $r
}

# Mostra o plano na tela, em portugues, antes de executar qualquer coisa.
function MostrarPlano {
    param([Parameter(Mandatory)] $Plano)

    Secao "Plano para esta maquina: $($Plano.Estrategia)"

    if ($Plano.Tarefas.Count -eq 0) {
        Erro 'nada a proteger'
    }

    foreach ($t in $Plano.Tarefas) {
        $rotulo = switch ($t.Tipo) {
            'vm'        { 'MAQUINA VIRTUAL' }
            'imagem'    { 'IMAGEM DO SERVIDOR' }
            'firebird'  { 'BANCO FIREBIRD' }
            'sqlserver' { 'BANCO SQL SERVER' }
            default     { $t.Tipo.ToUpper() }
        }
        Write-Host ("      {0,-20} {1}" -f $rotulo, $t.Nome) -ForegroundColor White
        Registrar ("      " + $rotulo + " " + $t.Nome)
        Nota "$($t.Frequencia) - $($t.Porque)"
    }

    # Fora de escopo POR DECISAO vem em cinza, nao em vermelho.
    #
    # Vermelho que nao significa problema treina o tecnico a ignorar vermelho -
    # e no dia em que houver um vermelho de verdade, ele passa batido.
    if ($Plano.PorDecisao.Count -gt 0) {
        Write-Host ""
        Write-Host "      FORA DO COFRE, DE PROPOSITO" -ForegroundColor DarkGray
        foreach ($d in $Plano.PorDecisao) { Nota $d }
    }

    if ($Plano.NaoProtegido.Count -gt 0) {
        Write-Host ""
        Write-Host "      NAO PROTEGIDO" -ForegroundColor Red
        foreach ($n in $Plano.NaoProtegido) { Erro $n }
    }

    if ($Plano.Avisos.Count -gt 0) {
        Write-Host ""
        foreach ($a in $Plano.Avisos) { Aviso $a }
    }
}
