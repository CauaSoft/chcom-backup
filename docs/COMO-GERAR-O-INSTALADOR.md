# Como gerar o instalador CH.Com Backup (.msi)

Guia para refazer o instalador quando sair uma versão nova do Duplicati.
Escrito depois de acertar o processo na tentativa e erro — cada armadilha
abaixo custou um build perdido.

## O que precisa estar instalado

| Ferramenta | Como instalar | Para quê |
|---|---|---|
| .NET SDK 10 | `winget install Microsoft.DotNet.SDK.10` | Compilar o Duplicati |
| WiX **5** | `dotnet tool install --global wix --version 5.0.2` | Montar o `.msi` |

O Duplicati exige o SDK **10** — está em `TargetFramework` dos `.csproj`.
Ter só o runtime não basta.

### Use WiX 5, não a versão mais recente

`dotnet tool install --global wix` sem `--version` instala o WiX 7, e ele
**para o build** com este erro:

```
error WIX7015: You must accept the Open Source Maintenance Fee (OSMF) EULA
to use WiX Toolset v7.
```

A partir da versão 6, o WiX passou a exigir aceitar um contrato de taxa de
manutenção para uso comercial. Não é um detalhe técnico que se contorna com
uma flag: é uma decisão de licenciamento e de custo, e cabe à CH.Com tomar.

O WiX **4 e 5 continuam livres** e são exatamente as versões para as quais o
Duplicati foi escrito — o código do ReleaseBuilder gera XML no namespace v4.
Por isso fixamos a 5.0.2. Não é um contorno: é a versão certa.

Se um dia quiser mesmo o WiX 7, será preciso avaliar a OSMF e aceitá-la
conscientemente.

## A chave de assinatura

Fica em `C:\dev\ch-backup-chaves\` e **não** está no repositório:

| Arquivo | O que é |
|---|---|
| `updater-chcom.key` | Chave que assina os manifestos de atualização |
| `senha-da-chave.txt` | A senha dela |

Ela foi criada uma vez com:

```powershell
dotnet run --project ReleaseBuilder -- create-key --password "SENHA" "C:/dev/ch-backup-chaves/updater-chcom.key"
```

**Guarde essa pasta no gerenciador de senhas e tire do disco.** Quem tem essa
chave consegue assinar uma atualização que os CH.Com Backup instalados nos
cartórios aceitariam como legítima. A senha num `.txt` ao lado da chave serve
para o build rodar, não é onde ela deve morar.

Se perder a chave, dá para gerar outra — mas as instalações antigas param de
aceitar atualizações assinadas pela nova, e cada cartório precisa ser
reinstalado à mão.

## O comando

```bash
cd /c/dev/ch-backup
export PATH="/c/Program Files/dotnet:$HOME/.dotnet/tools:$PATH"
export UPDATER_KEYFILE="C:/dev/ch-backup-chaves/updater-chcom.key"
export KEYFILE_PASSWORD="$(cat 'C:/dev/ch-backup-chaves/senha-da-chave.txt')"

yes Y | dotnet run --project ReleaseBuilder -- build Debug \
  --targets win-x64-gui.msi \
  --solution-file "C:/dev/ch-backup/Duplicati.slnx" \
  --git-stash-push=false \
  --disable-clean-source \
  --disable-authenticode \
  --disable-signcode \
  --disable-gpg-signing \
  --disable-s3-upload \
  --disable-github-upload \
  --disable-update-server-reload \
  --disable-discourse-announce \
  --disable-docker-push \
  --disable-notarize-signing \
  --allow-assembly-mismatch
```

## As armadilhas, uma por uma

**`--git-stash-push=false` é obrigatório.** O padrão dessa opção é **ligado**:
o build faz `git stash` antes de começar. Rodar sem essa flag guarda todo o
rebrand no stash e compila o Duplicati original — você recebe um MSI limpo,
sem a marca, e sem nenhum erro que explique por quê. Sempre confirme que a
árvore está commitada antes de buildar.

**`--disable-clean-source` também.** Sem ela o build limpa a árvore antes de
compilar, com o mesmo efeito.

**O caminho da solução precisa de barras normais.** O padrão que o build
assume está errado (`C:\dev\Duplicati.slnx`, sem a pasta do fork), então tem
que passar. E com `/`, não `\` — no Git Bash as barras invertidas somem e o
caminho chega grudado como `devch-backupDuplicati.slnx`.

**Precisa existir um `changelog-news.txt` na raiz.** Já existe no repositório,
com as notas da versão CH.Com. Se faltar, o build para logo no início.

**O `yes Y |` responde os prompts.** O build pergunta se pode continuar sem
Docker (usado para as imagens Linux, que não geramos). Sem responder, ele
fica travado esperando para sempre.

**`KEYFILE_PASSWORD` por variável de ambiente.** Se não estiver definida, o
build pede a senha no terminal — e falha se não houver console interativo.

## As correções nossas no ReleaseBuilder

Gerar MSI **no Windows** não funcionava no ReleaseBuilder original — o
caminho existe no código, mas nunca tinha sido exercitado. O build oficial do
Duplicati roda em Linux com `wixl`, que segue outro ramo e aceita a sintaxe
antiga do WiX.

Tudo corrigido neste fork. Se um dia você trouxer código novo do Duplicati
(`git merge upstream/master`), confira se estas correções sobreviveram — sem
elas o build volta a quebrar na etapa do WiX.

**A maior delas: a sintaxe dos arquivos é WiX v3, e o WiX v5 não a aceita.**
Não é só o namespace: a estrutura mudou. No v3 existe

```xml
<Wix><Product ...><Package ... /> ... </Product></Wix>
```

e no v4 o `Product` deixou de existir — virou o próprio `Package`. Sem
converter, o build para com `error WIX0005: The Wix element contains an
unexpected child element 'Product'`. O mesmo vale para `Condition` como texto,
`BinaryKey`/`FileKey` e os diretórios padrão.

A solução usa `wix convert`, a ferramenta oficial de migração, aplicada **só
nas cópias temporárias**. O repositório mantém os `.wxs` em v3, então o build
Linux continua funcionando e o merge com o upstream não conflita.

Detalhe traiçoeiro do `wix convert`: ele usa o **código de saída como
contador** de conversões aplicadas, não como sinal de erro. Converter 83
trechos devolve 83. Quem tratar não-zero como falha quebra o build justamente
quando a conversão deu certo.

As demais correções: o `xmlns=""` que anulava o namespace no gerador da lista
de arquivos; o `.wxi` que não era copiado junto com os `.wxs` (o WiX resolve
`<?include ?>` relativo à pasta do arquivo); e a variável `BuildEnv`, que
nenhum dos dois ramos definia — o `wixl` trata indefinida como vazia e pula o
trecho, o WiX real para com `WIX0150`.

Também é preciso ter a extensão Util do WiX instalada:

```powershell
wix extension add --global WixToolset.Util.wixext/5.0.2
```

**1. `xmlns=""` anulando o namespace** — em `ReleaseBuilder/WixHeatBuilder.cs`

O gerador da lista de arquivos criava os elementos com `doc.CreateElement(nome)`,
sem namespace. Como o `<Wix>` raiz tem um namespace padrão, o serializador
anula esse namespace em cada filho:

```xml
<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs"><Fragment xmlns="">
```

O WiX recusa com `error WIX0200: The Wix element contains an unhandled
extension element 'Fragment'`. A correção passa o namespace na criação, e os
filhos herdam.

**2. O `.wxi` não ia junto com os `.wxs`** — em `ReleaseBuilder/Build/Command.CreatePackage.cs`

Os `.wxs` são copiados para a pasta temporária para trocar o namespace, mas o
`Duplicati.wxs` começa com `<?include UpgradeData.wxi ?>`, e o WiX resolve
includes **relativos à pasta do arquivo**. Como o `.wxi` ficou para trás, o
build morria com `error WIX0103: Cannot find the include file`. A correção
copia os `.wxi` junto.

Por que o Duplicati não vê esses bugs: o build oficial deles roda em Linux com
`wixl`, que segue outro caminho no código e usa o namespace antigo.

## O que o build muda na árvore

Ele reescreve arquivos do repositório: as versões de cache nos HTML
(`?v=2.0.0.7` vira `?v=<versão>`), os arquivos de auto-update, o
`VersionTag.txt`, os `UpgradeData.wxi` e o `changelog.txt`. Também baixa o
ngclient do npm para dentro de `webroot/ngclient/`.

Isso é esperado. Depois do build, revise com `git diff` e decida o que
commitar. Os arquivos do ngclient vindos do npm **não** devem ser commitados.

Note que nossos `?v=chcom-N` sobrevivem — o build só troca a versão antiga do
Duplicati, não os nossos marcadores.

## O resultado não é assinado

O MSI sai **sem assinatura digital Authenticode**, porque `--disable-authenticode`
foi o que permitiu compilar sem um certificado de code signing.

Na prática: ao instalar num cartório, o Windows mostra **"Editor
desconhecido"** e o SmartScreen pode barrar na primeira execução. Funciona,
mas passa uma impressão ruim para o cliente.

Para resolver de verdade é preciso um **certificado EV de code signing**
(emitido para a CH.Com Soluções em Tecnologia, custa na faixa de centenas de
dólares por ano). Com ele, aponte `AUTHENTICODE_PFXFILE` e
`AUTHENTICODE_PASSWORD` e tire o `--disable-authenticode` do comando.

## Onde sai o arquivo

Em `build-temp/`, dentro da pasta do alvo. Procure por `*.msi`.
