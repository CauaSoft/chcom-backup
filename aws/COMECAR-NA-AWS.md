# Começar na AWS — 20 minutos, uma vez só

Isto é o que falta para o Cofre sair do papel. Não é código: é conta.

Faça na ordem. O que estiver entre `<>` você troca.

---

## 1. O bucket

Console da AWS → **S3** → *Criar bucket*.

| Campo | Valor | Por quê |
|---|---|---|
| Nome | `backup-aws-ch` | é o que o Cofre já espera |
| Região | **US East (Ohio) / us-east-2** | mais barato que São Paulo, e para backup a latência não importa |
| Bloquear acesso público | **ligado** (o padrão) | não mexa |
| Versionamento | **ligado** | obrigatório para o passo seguinte |
| **Bloqueio de objeto** | **ligado** | ver abaixo |

### Por que Bloqueio de objeto

Hoje, quem tem a credencial do cartório **pode apagar o backup daquele cartório**.

Esse é o roteiro do ransomware atual: invade o servidor, acha a credencial,
apaga o backup na nuvem, e **só então** cifra a máquina. O `rclone.conf` está
no servidor. A credencial está nele.

Com Bloqueio de objeto, um "apagar" não apaga: vira marcador, e a versão
continua lá até a retenção vencer.

Depois de ligado **não dá para desligar**, nem suspender o versionamento.

### Modo GOVERNANCE, não COMPLIANCE

Depois de criar, em *Propriedades → Bloqueio de objeto → Editar*:

- Modo: **Governança**
- Retenção padrão: **180 dias**

180 dias porque é o mínimo que o Deep Archive já cobra de qualquer jeito -
então essa retenção não custa um centavo a mais.

Governança e não Conformidade: em Governança, uma conta com a permissão
`s3:BypassGovernanceRetention` ainda consegue remover se você errar. Em
Conformidade **nem a conta raiz consegue** - se subir 2 TB errados, você paga
os 180 dias inteiros sem saída.

---

## 2. O usuário de cada cartório

Um usuário por cartório. Não reaproveite: o objetivo é que uma credencial
vazada pare no backup de **um** cartório.

Console → **IAM** → *Políticas* → *Criar política* → aba **JSON**.

Cole o conteúdo de `politica-cartorio.json` e **troque `CARTORIO`** pelo nome
curto do cartório - o mesmo que você vai digitar no assistente. Exemplo:
`cartorio-01`.

Nome da política: `cofre-cartorio-01`.

Depois → *Usuários* → *Criar usuário*:

- Nome: `cofre-cartorio-01`
- **NÃO** marque acesso ao console. Este usuário nunca faz login.
- Anexe a política `cofre-cartorio-01`
- Crie uma **chave de acesso** → tipo *Aplicativo em execução fora da AWS*

A **Secret Access Key aparece uma vez só**. É ela que vai no passo 4 do
assistente.

### O que essa política permite, e o que não permite

Permite, **só dentro do prefixo daquele cartório**: listar, enviar, baixar e
descongelar.

Não permite:

- **`s3:DeleteObject`** - o agente nunca apaga nada. Quem apaga é a regra de
  ciclo de vida do bucket, que o servidor não controla. Se o servidor for
  invadido, o invasor não tem como pedir a exclusão.
- Ver ou ler qualquer outro cartório. A condição `s3:prefix` no `ListBucket`
  faz o `rclone ls` na raiz devolver *Access Denied* - de propósito.

O menu escondido no programa é conforto. **A tranca é esta política.**

---

## 3. O seu usuário, o do gerente

Mesma coisa, com `politica-gerente.json`. Nome: `cofre-gerente`.

Ele lê o parque inteiro e descongela qualquer cartório - mas **não tem
`PutObject`**. A máquina do gerente não escreve no Cofre de ninguém.

---

## 4. Rodar o assistente

No servidor do cartório, `CONFIGURAR.bat`. No passo 4 entram as duas chaves.

O **passo 6 sobe uma sonda de 8 MB** e confere que ela chegou inteira,
provando a credencial antes de você mandar 100 GB. A sonda **fica lá**, em
STANDARD, num caminho fixo — testar de novo sobrescreve em vez de acumular.

Ela não é apagada de propósito: assim o agente nunca precisa da permissão de
apagar, e a política acima não a concede. Custa menos de um centavo por mês no
parque inteiro.

Se falhar ali, o erro da AWS diz exatamente qual permissão faltou.

---

## 5. O primeiro envio

Mande uma **pasta pequena**, uns poucos MB. Prova o caminho inteiro igual a
100 GB, e o Deep Archive cobra 180 dias de qualquer coisa que subir - mesmo
apagada amanhã.

Se der certo, no console da AWS você vê:

```
backup-aws-ch/cartorio-01/SERVIDOR-01/E/2026-08-27/...
```

Pastas legíveis. Arquivos cifrados.
