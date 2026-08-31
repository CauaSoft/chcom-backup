<#
================================================================================
  CH.Com Cofre - diagnostico

  Diz o que este servidor tem, o que falta, e se a arquitetura do Cofre serve
  aqui. NAO ALTERA NADA. Pode rodar a vontade, em horario comercial.

  E o primeiro programa a rodar num servidor novo. O veredito no fim responde
  uma pergunta so: da para proteger este servidor com o Cofre, e a que custo
  de tempo por noite.

  USO
      Dois cliques em DIAGNOSTICO-COFRE.bat
================================================================================
#>

[CmdletBinding()]
param(
    # Quanto tempo medir a velocidade de subida, em segundos.
    [int]$SegundosDeTeste = 12,

    # Pular o teste de velocidade (util em rede de cliente com franquia)
    [switch]$SemTesteDeLink
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $raiz 'modulos\comum.ps1')
. (Join-Path $raiz 'modulos\descobrir.ps1')

# Onde ficam configuracao, estado e historico. NAO e a pasta do codigo:
# Program Files e somente leitura para quem nao e administrador.
$dados = PastaDeDados $raiz

DesligarCliqueQueTrava
IniciarRegistro (CaminhoDe $env:USERPROFILE 'Desktop') 'diagnostico-cofre'

$problemas = @()
$avisos    = @()

Marca
Titulo 'Diagnostico - o que este servidor tem'

# ==============================================================================
#  1. A maquina
# ==============================================================================
$a = DescobrirAmbiente

Secao '1. A maquina'
Ok "$($a.Maquina) - $($a.Windows)"

if ($a.EhServer) {
    Ok 'edicao Server'
} else {
    Aviso 'esta e uma edicao CLIENT do Windows, nao Server'
    Nota 'O Cofre funciona: o export usa o VSS de dentro da VM, que existe aqui.'
    Nota 'Mas cartorio em producao nao deveria rodar em Windows client.'
    $avisos += 'Windows client em vez de Server'
}

# ==============================================================================
#  2. Hyper-V e as VMs
# ==============================================================================
Secao '2. Hyper-V'

if (-not $a.EhHost) {
    Aviso $a.HyperVNota
    if ($a.Windows -like '*Windows 11*' -or $a.Windows -like '*Windows 10*') {
        Nota 'Para ligar no Windows 11 Pro, em PowerShell como Administrador:'
        Nota '  Enable-WindowsOptionalFeature -Online -All -FeatureName Microsoft-Hyper-V'
        Nota 'Reinicia a maquina no fim.'
    } else {
        Nota 'Para ligar no Windows Server, em PowerShell como Administrador:'
        Nota '  Install-WindowsFeature -Name Hyper-V -IncludeManagementTools -Restart'
    }
    $avisos += 'sem Hyper-V - o Cofre so vai proteger arquivos e bancos aqui'
} else {
    Ok "Hyper-V ligado, $($a.VMs.Count) maquina(s) virtual(is)"

    $totalVM = 0
    $maiorVM = 0
    foreach ($v in $a.VMs) {
        $totalVM += $v.TamanhoBytes
        if ($v.TamanhoBytes -gt $maiorVM) { $maiorVM = $v.TamanhoBytes }

        $estado = if ($v.Estado -eq 'Running') { 'ligada' } else { $v.Estado }
        Write-Host ("      {0,-28} {1,-10} {2,10}" -f $v.Nome, $estado, (Tamanho $v.TamanhoBytes)) -ForegroundColor Gray
        Registrar ("      " + $v.Nome + " " + $estado + " " + (Tamanho $v.TamanhoBytes))

        if ($v.Estado -eq 'Running' -and -not $v.VssNoConvidado) {
            Aviso "  $($v.Nome): sem o servico de backup do convidado"
            Nota  "  O export desta VM sai CRASH-CONSISTENT, nao application-consistent."
            Nota  "  Instale os Servicos de Integracao dentro da VM."
            $avisos += "VM $($v.Nome) sem VSS no convidado"
        }
    }
    Nota "somadas: $(Tamanho $totalVM)   maior VM: $(Tamanho $maiorVM)"
    $script:TotalVM = $totalVM
    $script:MaiorVM = $maiorVM
}

# ==============================================================================
#  3. Bancos de dados
# ==============================================================================
Secao '3. Bancos de dados'

if ($a.Firebird.Count -gt 0) {
    Ok "Firebird encontrado ($($a.Firebird.Count) instalacao(oes))"
    foreach ($f in $a.Firebird) { Nota "gbak: $($f.Gbak)  $($f.Versao)" }
    Nota 'O Cofre vai usar gbak. Copiar o .fdb aberto nao e backup valido.'
} else {
    Nota 'nenhum Firebird nesta maquina'
}

if ($a.SqlServer.Count -gt 0) {
    Ok "SQL Server encontrado ($($a.SqlServer.Count) instancia(s))"
    foreach ($s in $a.SqlServer) { Nota "$($s.Instancia)  ($($s.Estado))" }
} else {
    Nota 'nenhum SQL Server nesta maquina'
}

if ($a.Firebird.Count -eq 0 -and $a.SqlServer.Count -eq 0 -and $a.EhHost) {
    Nota 'Normal num host: os bancos costumam morar DENTRO das VMs.'
    Nota 'O Cofre precisa ser instalado tambem dentro de cada VM que tenha banco.'
}

# ==============================================================================
#  4. Espaco em disco
#
#  O Export-VM escreve a VM inteira em disco antes de subir. Sem espaco para a
#  MAIOR VM, o Cofre nao roda - e descobrir isso as 2 da manha, com a exportacao
#  pela metade, e o pior momento possivel.
# ==============================================================================
Secao '4. Espaco para trabalhar'

$precisa = if ($script:MaiorVM) { [long]($script:MaiorVM * 1.2) } else { 20GB }
$melhorDisco = $null

foreach ($d in ($a.Discos | Sort-Object LivreBytes -Descending)) {
    $temEspaco = ($d.LivreBytes -ge $precisa)

    # So disco LOCAL FIXO serve de area de trabalho. Um OneDrive mapeado como
    # unidade de rede tem espaco de sobra e seria a pior escolha possivel:
    # exportar 200 GB de VM para dentro dele empurra 200 GB para a nuvem
    # errada, devagar, e estoura a conta do cliente.
    $marca = if (-not $d.ServeParaTrabalho) { "$($d.Tipo) - nao serve" }
             elseif ($temEspaco)            { 'serve' }
             else                            { 'espaco insuficiente' }

    Write-Host ("      {0}:  livre {1,10}   {2}" -f $d.Unidade, (Tamanho $d.LivreBytes), $marca) -ForegroundColor Gray
    Registrar ("      " + $d.Unidade + ": livre " + (Tamanho $d.LivreBytes) + " " + $marca)

    if (-not $melhorDisco -and $d.ServeParaTrabalho -and $temEspaco) { $melhorDisco = $d }
}

Nota "necessario: $(Tamanho $precisa)  (maior VM + 20% de folga)"

if ($melhorDisco) {
    Ok "usar a unidade $($melhorDisco.Unidade): como area de trabalho"
} else {
    $locais = @($a.Discos | Where-Object { $_.ServeParaTrabalho })
    if ($locais.Count -eq 0) {
        Erro 'nenhum disco local fixo encontrado nesta maquina'
    } else {
        Erro 'nenhum disco LOCAL tem espaco para exportar a maior VM'
        Nota 'Unidade de rede nao serve de area de trabalho, mesmo com espaco.'
    }
    Nota 'Opcoes: liberar espaco, ou acrescentar um disco ao servidor.'
    $problemas += 'sem disco local com espaco para o export'
}
# ==============================================================================
#  5. Ferramentas
# ==============================================================================
Secao '5. Ferramentas do Cofre'

$rclone = CaminhoDe $raiz 'rclone.exe'
if (Test-Path $rclone) {
    $v = ''
    try { $v = (& $rclone version | Select-Object -First 1) } catch { }
    Ok "rclone presente  $v"
} else {
    Aviso 'rclone.exe ainda nao esta nesta pasta'
    Nota 'O INSTALAR.bat traz o rclone embutido; se faltar, baixa do site oficial (rclone.org), ~20 MB.'
    $avisos += 'rclone ausente'
}

$config = CaminhoDe $dados 'cofre.conf'
if (Test-Path $config) {
    Ok 'configuracao do Cofre encontrada'
} else {
    Aviso 'este servidor ainda nao foi configurado'
    Nota 'Rode o CONFIGURAR.bat: ele gera a chave e configura o destino.'
    $avisos += 'nao configurado'
}

# ==============================================================================
#  6. Velocidade de subida
#
#  O numero que decide se a arquitetura serve aqui. Uma VM de 200 GB num link
#  de 10 Mbps leva 44 horas - nao cabe numa janela noturna, e nao adianta
#  descobrir isso depois de instalar em 50 cartorios.
# ==============================================================================
Secao '6. Velocidade de subida'

$mbps = 0
if ($SemTesteDeLink) {
    Nota 'teste de link pulado (-SemTesteDeLink)'
} else {
    Passo "medindo por $SegundosDeTeste segundos..."
    try {
        # Sobe dados descartaveis para um servico publico de teste. Nao envia
        # nada do cartorio: o corpo e feito de zeros gerados na hora.
        $bloco = New-Object byte[] (1MB)
        $enviados = 0
        $relogio = [Diagnostics.Stopwatch]::StartNew()

        while ($relogio.Elapsed.TotalSeconds -lt $SegundosDeTeste) {
            $req = [Net.HttpWebRequest]::Create('https://httpbin.org/post')
            $req.Method = 'POST'
            $req.Timeout = 20000
            $req.ContentType = 'application/octet-stream'
            $req.ContentLength = $bloco.Length
            $fluxo = $req.GetRequestStream()
            $fluxo.Write($bloco, 0, $bloco.Length)
            $fluxo.Close()
            $resp = $req.GetResponse()
            $resp.Close()
            $enviados += $bloco.Length
        }
        $relogio.Stop()

        $mbps = [math]::Round(($enviados * 8) / $relogio.Elapsed.TotalSeconds / 1MB, 1)
        Ok "subida medida: $mbps Mbps"
        Nota 'ATENCAO: esta medida e um PISO, nao a velocidade real para a AWS.'
        Nota 'Ela usa um servidor publico de teste, que costuma ser mais lento'
        Nota 'que o S3. A medida que vale e a do CONFIGURAR.bat, que sobe'
        Nota 'um arquivo de verdade para o bucket do cartorio.'
        Nota 'Se ja aqui o numero for baixo, o real dificilmente sera melhor.'
    } catch {
        Aviso "nao consegui medir: $($_.Exception.Message)"
        Nota 'Sem internet, ou o proxy do cartorio bloqueou. Meca de outro jeito.'
        $avisos += 'velocidade de subida nao medida'
    }
}

# ==============================================================================
#  7. Veredito
#
#  A conta que interessa: com o que existe aqui, quanto tempo leva uma noite
#  de Cofre - e cabe na janela?
# ==============================================================================
Secao '7. O que isso significa'

if ($script:TotalVM -and $mbps -gt 0) {
    # Compressao real de .vhdx varia muito. 50% e conservador para VM Windows
    # com disco dinamico; disco fixo comprime bem mais.
    $comprimido = $script:TotalVM * 0.5
    $segundos = ($comprimido * 8) / ($mbps * 1MB)
    $horas = [math]::Round($segundos / 3600, 1)

    Nota "VMs somadas: $(Tamanho $script:TotalVM)"
    Nota "estimando ~50% de compressao: $(Tamanho $comprimido) para subir"
    Nota "a $mbps Mbps: aproximadamente $horas horas por rodada completa"
    Write-Host ""

    if ($horas -le 8) {
        Ok 'cabe numa janela noturna - envio mensal das VMs sem aperto'
    } elseif ($horas -le 24) {
        Aviso 'nao cabe numa noite, mas cabe num fim de semana'
        Nota  'Sugestao: uma VM por noite, em vez de todas de uma vez.'
        $avisos += 'envio completo passa de 8 horas'
    } elseif ($horas -le 72) {
        Aviso 'a primeira carga leva dias'
        Nota  'Continua viavel para DR mensal, mas a carga inicial precisa ser planejada.'
        $avisos += "envio completo leva $horas horas"
    } else {
        Erro "com este link, uma rodada completa levaria $horas horas"
        Nota 'Nao e viavel subir as VMs deste servidor por este link.'
        Nota 'Opcoes: mais banda, proteger so os bancos e arquivos daqui, ou'
        Nota 'levar a carga inicial em disco fisico (AWS Snowball).'
        $problemas += "link insuficiente para as VMs ($horas h)"
    }
}

# --- resultado final ----------------------------------------------------------
Write-Host ""
if ($problemas.Count -eq 0 -and $avisos.Count -eq 0) {
    Caixa @('ESTE SERVIDOR ESTA PRONTO PARA O COFRE',
            '',
            'Rode o CONFIGURAR.bat para configurar.') 'Green'
} elseif ($problemas.Count -eq 0) {
    Caixa @("PRONTO, COM $($avisos.Count) OBSERVACAO(OES)",
            '',
            'Da para seguir. Leia os avisos acima antes.') 'Yellow'
    foreach ($x in $avisos) { Write-Host "    - $x" -ForegroundColor Yellow; Registrar "    - $x" }
} else {
    Caixa @("$($problemas.Count) PROBLEMA(S) IMPEDEM O COFRE AQUI") 'Red'
    foreach ($x in $problemas) { Write-Host "    - $x" -ForegroundColor Red; Registrar "    - $x" }
    if ($avisos.Count -gt 0) {
        Write-Host ""
        foreach ($x in $avisos) { Write-Host "    - $x" -ForegroundColor Yellow; Registrar "    - $x" }
    }
}

Write-Host ""
if ($script:ArquivoLog) {
    Nota "relatorio salvo em: $script:ArquivoLog"
    Nota 'Mande este arquivo ao suporte se precisar de ajuda.'
}
Write-Host ""
