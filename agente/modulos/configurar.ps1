<#
================================================================================
  CH.Com Cofre - configuracao, chave e destino

  A CHAVE E O ATIVO MAIS IMPORTANTE DO SISTEMA INTEIRO.

  O rclone cifra tudo neste servidor antes de qualquer byte sair. A AWS recebe
  conteudo cifrado e nomes de arquivo cifrados - nem a Amazon, nem quem tiver
  as credenciais da conta, consegue ler.

  O preco disso: SEM A CHAVE, O QUE ESTA NA AWS E LIXO IRRECUPERAVEL.

  E dai vem a regra que este arquivo existe para cumprir: a chave nao pode
  viver so no servidor do cartorio. Se o cartorio pegar fogo - que e o cenario
  para o qual o Cofre existe - o backup morreria junto com ele.

  Tres lugares, e um deles fora do cartorio:
     1. o servidor (para o envio funcionar)
     2. o cofre de senhas do gerente, fora da cidade
     3. papel, em envelope lacrado

  O instalador NAO DEIXA CONTINUAR sem a confirmacao de que foi guardada.
================================================================================
#>

<#
    Gera a chave.

    Usa o gerador criptografico do Windows, nao Get-Random. Get-Random e
    previsivel o bastante para nao servir de chave - ele existe para sortear
    numero, nao para proteger o backup de um cartorio.

    Duas senhas: uma cifra o conteudo, outra cifra os nomes de arquivo. E o
    formato que o rclone crypt espera.
#>
function GerarChave {
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $a = New-Object byte[] 32
        $b = New-Object byte[] 32
        $rng.GetBytes($a)
        $rng.GetBytes($b)
        return [PSCustomObject]@{
            Conteudo = [Convert]::ToBase64String($a)
            Nomes    = [Convert]::ToBase64String($b)
            Gerada   = (Get-Date).ToUniversalTime().ToString('o')
        }
    } finally {
        $rng.Dispose()
    }
}

<#
    Escreve o rclone.conf.

    Dois remotos encadeados:

      cofre-s3    fala com a AWS. Guarda as credenciais e a regiao.
      cofre       envolve o anterior com criptografia. E este que o motor usa.

    Assim tudo que passa por "cofre:" e cifrado antes de chegar no S3, sem o
    resto do sistema precisar saber que existe criptografia.

    As senhas vao OFUSCADAS, no formato do proprio rclone. Ofuscar nao e
    cifrar - quem tem o arquivo tem a chave - e por isso o arquivo fica com
    permissao restrita e nunca sai do servidor.
#>
function EscreverRcloneConf {
    param(
        [Parameter(Mandatory)] [string]$Rclone,
        [Parameter(Mandatory)] [string]$Arquivo,
        [Parameter(Mandatory)] [string]$ChaveAws,
        [Parameter(Mandatory)] [string]$SegredoAws,
        [Parameter(Mandatory)] [string]$Regiao,
        [Parameter(Mandatory)] [string]$Bucket,
        [Parameter(Mandatory)] $Chave
    )

    <#
        SEM 2>&1 aqui, de proposito.

        Juntar o stderr ao stdout de um programa externo, com
        ErrorActionPreference = Stop, faz cada linha de stderr virar erro
        terminante - e o rclone escreve aviso em stderr por qualquer motivo.
        Aqui isso mataria o assistente na hora de gerar o rclone.conf, com uma
        mensagem que nao tem nada a ver.

        O que interessa e o stdout: a senha embaralhada.
    #>
    $senhaConteudo = & $Rclone obscure $Chave.Conteudo
    $senhaNomes    = & $Rclone obscure $Chave.Nomes
    if (-not $senhaConteudo -or -not $senhaNomes) {
        throw 'o rclone nao conseguiu embaralhar a chave - verifique se o rclone.exe esta inteiro.'
    }

    $texto = @"
[cofre-s3]
type = s3
provider = AWS
access_key_id = $ChaveAws
secret_access_key = $SegredoAws
region = $Regiao
location_constraint = $Regiao
acl = private
server_side_encryption = AES256

[cofre]
type = crypt
remote = cofre-s3:$Bucket
filename_encryption = standard
directory_name_encryption = false
password = $senhaConteudo
password2 = $senhaNomes
"@

    [System.IO.File]::WriteAllText($Arquivo, $texto, [System.Text.UTF8Encoding]::new($false))
    RestringirAcesso $Arquivo
}

<#
    Tira o acesso de todo mundo, menos administradores e o sistema.

    Um rclone.conf legivel por qualquer usuario da maquina entrega o backup
    inteiro do cartorio para quem passar por ali. Herdar as permissoes da
    pasta nao basta: a heranca e removida de proposito.
#>
function RestringirAcesso([string]$arquivo) {
    try {
        $acl = Get-Acl $arquivo
        $acl.SetAccessRuleProtection($true, $false)   # nao herda nada
        foreach ($r in @($acl.Access)) { [void]$acl.RemoveAccessRule($r) }
        foreach ($quem in @('BUILTIN\Administrators', 'NT AUTHORITY\SYSTEM')) {
            $regra = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $quem, 'FullControl', 'None', 'None', 'Allow')
            $acl.AddAccessRule($regra)
        }
        Set-Acl -Path $arquivo -AclObject $acl
        return $true
    } catch {
        return $false
    }
}

<#
    O papel da chave, para o envelope lacrado.

    Escrito em arquivo de texto para ser IMPRESSO e depois apagado. Nao fica
    no servidor: a copia que importa e a de papel, guardada fora do cartorio.

    Vai com o procedimento de recuperacao junto, porque quem abrir esse
    envelope daqui a dois anos, num dia ruim, nao vai lembrar de nada.
#>
function EscreverPapelDaChave {
    param(
        [Parameter(Mandatory)] [string]$Arquivo,
        [Parameter(Mandatory)] $Chave,
        [Parameter(Mandatory)] [string]$Cartorio,
        [Parameter(Mandatory)] [string]$Maquina,
        [Parameter(Mandatory)] [string]$Bucket
    )

    $texto = @"
================================================================================
  CH.Com Cofre - CHAVE DE RECUPERACAO
  GUARDE ESTE PAPEL FORA DO CARTORIO
================================================================================

  Cartorio : $Cartorio
  Servidor : $Maquina
  Bucket   : $Bucket
  Gerada   : $((Get-Date).ToString('dd/MM/yyyy HH:mm'))

--------------------------------------------------------------------------------
  SEM ESTES DOIS CODIGOS, O BACKUP NA AWS NAO PODE SER LIDO POR NINGUEM.
  Nem pela CH.Com, nem pela Amazon, nem por quem tiver a senha da conta.
--------------------------------------------------------------------------------

  CHAVE 1 (conteudo dos arquivos)

      $($Chave.Conteudo)

  CHAVE 2 (nomes dos arquivos)

      $($Chave.Nomes)

--------------------------------------------------------------------------------
  COMO USAR, NO DIA EM QUE PRECISAR
--------------------------------------------------------------------------------

  1. Instale o CH.Com Cofre em qualquer computador com Windows.
  2. Abra o programa e va em "Restaurar".
  3. Ele vai pedir estas duas chaves e as credenciais da AWS.
  4. A partir dai o programa lista o que existe na nuvem e restaura.

  ATENCAO AO TEMPO: os dados ficam no S3 Glacier Deep Archive, que e barato
  justamente porque nao e imediato. Depois de pedir a recuperacao, o tempo de
  espera e de 12 horas (modo rapido) ou ate 48 horas (modo economico). Isto
  nao tem como acelerar - planeje contando com essa espera.

--------------------------------------------------------------------------------
  ONDE ESTE PAPEL DEVE ESTAR
--------------------------------------------------------------------------------

  [ ] envelope lacrado, em local diferente do cartorio
  [ ] cofre de senhas do gerente da CH.Com
  [ ] NUNCA por e-mail, WhatsApp ou pasta compartilhada

  Se este papel se perder E o servidor for destruido, o backup esta perdido.
  Nao ha recuperacao, nao ha suporte que resolva, nao ha excecao.

================================================================================
  CH.Com Solucoes em Tecnologia
================================================================================
"@

    [System.IO.File]::WriteAllText($Arquivo, $texto, [System.Text.UTF8Encoding]::new($true))
}

# Le e grava o cofre.conf, que guarda o que NAO e segredo: nome do cartorio,
# pasta de trabalho, agendamento. Credencial e chave ficam no rclone.conf.
<#
    Le o cofre.conf - e garante que ele tenha TODOS os campos.

    ConvertFrom-Json devolve um PSCustomObject, e PSCustomObject nao aceita
    propriedade nova por atribuicao. Entao um cofre.conf gravado por uma
    versao anterior - sem os campos criados depois - fazia a tela de
    configuracao ESTOURAR na hora de salvar, e a janela inteira sumia.

    A correcao nao e no botao Salvar: e aqui. O que foi lido e despejado por
    cima de uma configuracao nova. O que existe no arquivo vence; o que nao
    existe ganha o padrao. O resto do programa recebe sempre uma configuracao
    completa, e campo novo no futuro nao quebra instalacao antiga.
#>
function LerConfiguracao([string]$arquivo) {
    if (-not (Test-Path $arquivo)) { return $null }
    $lido = $null
    try { $lido = (Get-Content $arquivo -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
    if (-not $lido) { return $null }

    $cfg = NovaConfiguracao
    foreach ($p in $lido.PSObject.Properties) { $cfg[$p.Name] = $p.Value }
    return $cfg
}

function GravarConfiguracao([string]$arquivo, $config) {
    $json = $config | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText($arquivo, $json, [System.Text.UTF8Encoding]::new($false))
}

function NovaConfiguracao {
    return [ordered]@{
        Versao           = 1
        Cartorio         = ''
        Remoto           = 'cofre'
        Bucket           = 'backup-aws-ch'
        Regiao           = 'us-east-2'
        PastaDeTrabalho  = ''
        Pastas           = @()
        Discos           = @()
        MbpsMedido       = 0
        BancoFirebird    = ''
        ManterCopiaLocal = $false
        UrlPainel        = ''
        TokenPainel      = ''
        Criada           = (Get-Date).ToUniversalTime().ToString('o')
    }
}
