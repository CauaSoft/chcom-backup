# CH.Com Backup - instalacao no servidor do cartorio

> **Clonou o repositorio?** A pasta `marca/`, que este instalador precisa, e
> GERADA e nao fica versionada. Antes de levar esta pasta para um servidor,
> monte o pacote:
>
> ```powershell
> cd marca
> .\gerar-oem-js.ps1     # junta versoes.js dentro do oem-custom.js
> .\criar-pacote.ps1     # monta dist/ com a pasta marca/ dentro
> ```
>
> O passo a passo esta em [`docs/COMO-GERAR-O-INSTALADOR.md`](../docs/COMO-GERAR-O-INSTALADOR.md).


Este pacote aplica a identidade visual da CH.Com no Duplicati e configura o
envio dos relatórios para o Painel Backup CH.Com.

## Instalação — dois cliques

**1.** Copie esta **pasta inteira** para o servidor.

**2.** Dê **duplo clique em `INSTALAR.bat`**.

**3.** Clique em **Sim** no aviso do Windows.

Pronto. Ele faz o resto sozinho e para no final para você ler o resultado.

Depois, abra o Duplicati no navegador e pressione **Ctrl+F5**.

> Copie a **pasta inteira**, não só o `INSTALAR.bat` — ele precisa da pasta
> `marca` que está ao lado.

## Não precisa ter o Duplicati instalado

Se o servidor estiver limpo, **o instalador baixa e instala o Duplicati
sozinho** (cerca de 90 MB, do site oficial) e depois aplica a marca.

Se o servidor não tiver internet, baixe o `.msi` em
<https://duplicati.com/download> (Windows 64-bit), **coloque o arquivo dentro
desta pasta** e rode o `INSTALAR.bat`. Ele usa o arquivo local em vez de
baixar.

Se o Duplicati já estiver instalado, ele acha sozinho — inclusive em outro
disco ou em pasta fora do padrão.

## O que o instalador faz

1. Procura o Duplicati; se não achar, baixa e instala
2. Para o Duplicati (e o serviço, se houver)
3. Guarda uma cópia intacta de cada arquivo original que vai substituir
4. Aplica a marca CH.Com
5. **Religa o Duplicati e confirma que voltou** — mesmo se algo falhar no meio

## Ligar no painel (opcional, depois)

Para este servidor mandar os relatórios ao Painel Backup CH.Com, use o script
direto, com o token do cartório:

```powershell
.\aplicar-no-cartorio.ps1 -Token SEU-TOKEN -UrlPainel https://painel.chcom.com.br
```

Ele pede a senha do Duplicati numa janela com asteriscos.

**Ele nunca apaga a configuração de envio que já existir.** Se o cartório já
manda relatório para outro sistema, a URL do painel é **acrescentada** à
lista — o envio antigo continua funcionando. Isso aparece na tela ao final,
quando acontece.

## As ferramentas — dois cliques cada

| Arquivo | O que faz |
|---|---|
| `DIAGNOSTICO.bat` | diz o que está instalado, o que falta, se o programa caiu e quando o backup rodou |
| `RESUMIR-AVISOS.bat` | mostra os avisos do backup **agrupados por tipo**, com um exemplo de cada |
| `APLICAR-REGRAS.bat` | aplica as regras padrão (filtros, cópia de arquivo aberto, novas tentativas) |
| `DEFINIR-SENHA.bat` | define uma senha nova, sem precisar saber a atual |
| `CORRIGIR-S3.bat` | conserta o erro `s3-aws is not supported` |
| `DESINSTALAR.bat` | tira a marca e devolve o Duplicati original |

O `DIAGNOSTICO.bat` e o `RESUMIR-AVISOS.bat` **não alteram nada**, só olham.
Pode rodar à vontade.

### Por que o RESUMIR-AVISOS existe

Um backup grande gera milhares de linhas de aviso, e quase todas são a mesma
coisa repetida — o mesmo motivo, caminhos diferentes. Mandar esse log inteiro
para alguém analisar não ajuda: some no meio do volume.

O `RESUMIR-AVISOS.bat` lê os relatórios que o próprio programa já guardou e
mostra assim:

```
     20x  PermissionDenied
          Excluding path due to permission denied: C:\Windows\CSC\v2.0.6\
      8x  UnsupportedOption
          The supplied option ---*\pagefile.sys is not supported

    O QUE FAZER
    Ha opcao invalida gravada (nome comecando com tres tracos ou mais).
    Rode o APLICAR-REGRAS.bat: ele apaga essas e grava no lugar certo.
```

Cabe numa tela. **Tire um print e mande** — é tudo que o suporte precisa ver.
Ele roda **no servidor do cartório**, e pede a senha do CH.Com Backup daquele
servidor.

## Situações comuns

**"Este script precisa ser executado como Administrador"** — você abriu o
PowerShell normal. Feche e abra com botão direito → Executar como
administrador.

**"Nao encontrei o Duplicati em..."** — ele está em outra pasta. Use
`-Destino`:

```powershell
.\aplicar-no-cartorio.ps1 -Destino "D:\Duplicati 2" -Token ... -UrlPainel ...
```

**"Senha do Duplicati recusada"** — a marca **já foi aplicada**; só o envio
não foi configurado. Rode de novo com a senha certa; pode rodar quantas vezes
quiser, não duplica nada.

**A tela continua com a cara antiga** — o navegador guarda os arquivos por
até 7 dias. Pressione **Ctrl+F5** para forçar a recarga.

**O certificado HTTPS do painel é próprio (autoassinado)** — acrescente
`-AceitarCertificadoInvalido`.

## Desfazer

```powershell
.\aplicar-no-cartorio.ps1 -Desfazer
```

Restaura os arquivos originais, guardados em
`C:\Program Files\Duplicati 2\backup-original-duplicati\`. O visual volta ao
Duplicati padrão.

Repare que **desfazer não desconfigura o envio de relatórios** — isso é de
propósito. Tirar a marca é uma decisão de aparência; parar de monitorar o
backup de um cartório é outra bem diferente, e não deve acontecer por
consequência. Para parar o envio, remova a opção `send-http-json-urls` nas
configurações do Duplicati.

## Sobre o software

O CH.Com Backup é uma versão modificada do **Duplicati**, software livre sob
licença MIT, Copyright (c) 2026 Duplicati Inc. Não é um produto oficial do
Duplicati, e o projeto original não presta suporte a esta versão.

O motor de backup é o mesmo: backups feitos aqui podem ser restaurados pelo
Duplicati original, e vice-versa.
