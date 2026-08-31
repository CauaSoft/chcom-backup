<#
================================================================================
  CH.Com Cofre - conferir na nuvem

  Responde uma pergunta so: ESTA TUDO LA?

  E responde LENDO A AWS, nao o proprio relatorio. Essa distincao e o ponto
  do arquivo. O estado.json diz o que o agente ACHA que enviou; um erro no
  agente aparece nos dois lugares ao mesmo tempo e ninguem descobre nada.
  Aqui a fonte e o bucket.

  NAO CUSTA RESGATE

  Listar objeto em Deep Archive e de graca e instantaneo - o que custa e
  BAIXAR. Entao da para conferir todo dia sem gastar nada: nome, tamanho e
  data vem do indice, nao do arquivo congelado.
================================================================================
#>

<#
    Le o que existe no prefixo deste cartorio.

    Devolve uma linha por item do plano, com a data mais recente encontrada na
    nuvem para ele - ou a falta dela, que e a resposta que interessa.
#>
function ConferirNaNuvem {
    param(
        [Parameter(Mandatory)] [string]$Rclone,
        [Parameter(Mandatory)] [string]$Config,
        [Parameter(Mandatory)] $Cartorio,
        [Parameter(Mandatory)] $Plano,
        [Parameter(Mandatory)] [string]$Servidor,
        [string]$Remoto = 'cofre'
    )

    $r = [PSCustomObject]@{ Itens = @(); Erro = $null; TotalBytes = 0; Lidos = 0 }

    $exec = RodarRclone -Rclone $Rclone -Argumentos @(
        'lsjson', "${Remoto}:$Cartorio", '--config', $Config, '--recursive')
    if ($exec.Codigo -ne 0) { $r.Erro = $exec.Erro; return $r }

    $tudo = LerListaDoRclone $exec.Saida

    <#
        O caminho na nuvem e <SERVIDOR>/<DISCO>/<DATA>/<NOME>/arquivos, porque
        a listagem ja parte de dentro do cartorio. O que identifica um item do
        plano e o par DISCO + NOME - e nao o nome sozinho: duas pastas
        chamadas "DADOS" em discos diferentes sao duas coisas diferentes.
    #>
    $porItem = @{}
    foreach ($o in $tudo) {
        if ($o.IsDir) { continue }
        $p = ([string]$o.Path) -split '/'
        if ($p.Count -lt 5) { continue }
        $srv = $p[0]; $disco = $p[1]; $data = $p[2]; $nome = $p[3]
        if ($data -notmatch '^\d{4}-\d{2}-\d{2}$') { continue }

        $chave = "$disco|$nome"
        if (-not $porItem.ContainsKey($chave)) {
            $porItem[$chave] = @{ Disco = $disco; Nome = $nome; Servidor = $srv
                                  Datas = @{}; Bytes = 0 }
        }
        $porItem[$chave].Bytes += [long]$o.Size
        $porItem[$chave].Datas[$data] = $true
        $r.TotalBytes += [long]$o.Size
        $r.Lidos++
    }

    return (MontarVeredito $r $porItem $Plano $Servidor)
}

<#
    Cruza o plano com o que a nuvem tem.

    A ordem do veredito importa. Um item pode estar na nuvem com data velha, e
    isso e pior do que parece: parece protegido na lista e nao esta. Entao a
    primeira pergunta e "existe?", a segunda e "de quando?".
#>
function MontarVeredito($r, $porItem, $Plano, [string]$Servidor) {
    $hoje = (Get-Date).Date

    foreach ($t in @($Plano.Tarefas)) {
        $disco = DiscoDaOrigem $t.Tipo ([string]$t.Alvo)
        $nome  = NomeParaDestino $t.Nome
        $chave = "$disco|$nome"

        $linha = [PSCustomObject]@{
            Nome = $t.Nome; Tipo = $t.Tipo; Disco = $disco
            NaNuvem = $false; UltimaData = $null; Dias = $null
            Bytes = 0; Copias = 0; Estado = 'erro'; Frase = ''
        }

        if ($porItem.ContainsKey($chave)) {
            $achado = $porItem[$chave]
            $datas = @($achado.Datas.Keys | Sort-Object -Descending)
            $linha.NaNuvem = $true
            $linha.UltimaData = $datas[0]
            $linha.Copias = $datas.Count
            $linha.Bytes = $achado.Bytes
            $d = DataOuNada $datas[0]
            if ($d) { $linha.Dias = [int]($hoje - $d.Date).TotalDays }
        }

        if (-not $linha.NaNuvem) {
            $linha.Estado = 'erro'
            $linha.Frase = 'NUNCA chegou na nuvem'
        } elseif ($null -eq $linha.Dias) {
            $linha.Estado = 'aviso'
            $linha.Frase = "esta la, mas a data nao faz sentido ($($linha.UltimaData))"
        } elseif ($linha.Dias -le 1) {
            $linha.Estado = 'ok'
            $linha.Frase = "$($linha.Copias) copia(s), a mais nova de hoje"
        } elseif ($linha.Dias -le 8) {
            $linha.Estado = 'ok'
            $linha.Frase = "$($linha.Copias) copia(s), a mais nova ha $($linha.Dias) dia(s)"
        } elseif ($linha.Dias -le 40) {
            $linha.Estado = 'aviso'
            $linha.Frase = "a mais nova tem $($linha.Dias) dias"
        } else {
            $linha.Estado = 'erro'
            $linha.Frase = "parado ha $($linha.Dias) dias"
        }
        $r.Itens += $linha
    }

    <#
        O que esta na nuvem e NAO esta no plano.

        Isso nao e erro - e um item que deixou de ser protegido: a pasta saiu
        da configuracao, a VM foi removida do host. Mas precisa aparecer,
        senao vira dado pago para sempre em Deep Archive sem ninguem lembrar
        por que.
    #>
    $doPlano = @{}
    foreach ($t in @($Plano.Tarefas)) {
        $doPlano["$(DiscoDaOrigem $t.Tipo ([string]$t.Alvo))|$(NomeParaDestino $t.Nome)"] = $true
    }
    foreach ($chave in @($porItem.Keys)) {
        if ($doPlano.ContainsKey($chave)) { continue }
        $a = $porItem[$chave]
        $datas = @($a.Datas.Keys | Sort-Object -Descending)
        $r.Itens += [PSCustomObject]@{
            Nome = $a.Nome; Tipo = 'orfao'; Disco = $a.Disco
            NaNuvem = $true; UltimaData = $datas[0]; Dias = $null
            Bytes = $a.Bytes; Copias = $datas.Count; Estado = 'aviso'
            Frase = 'esta na nuvem mas nao esta mais no plano deste servidor'
        }
    }
    return $r
}
