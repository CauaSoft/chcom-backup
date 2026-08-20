# Publicar o painel na internet

Hoje o painel roda na máquina do gerente, em `localhost:3000`. Isso funciona
para olhar, mas **os cartórios não conseguem mandar relatório para lá**: o
endereço é local, e `localhost` dentro do servidor do cartório aponta para o
próprio cartório.

Para os 38 reportarem sozinhos, o painel precisa de um endereço que eles
alcancem.

---

## O que o domínio resolve, e o que não resolve

O domínio é **só o nome**. Ele não hospeda nada: aponta para um endereço de
IP, e nesse endereço precisa existir uma máquina ligada 24 horas rodando o
painel.

**Hospedagem compartilhada não serve** (aquele plano com cPanel, onde se sobe
site por FTP). O painel é um programa que fica rodando o tempo todo com um
banco próprio; hospedagem compartilhada serve páginas, não processos.

**Serve um VPS** — uma máquina virtual Linux, sua, com IP público.

**Serve também uma máquina Linux da própria empresa**, ligada 24 horas. É o
caminho mais barato, e tem uma receita própria mais abaixo — mas antes leia o
teste do IP público, porque no Brasil ele decide qual dos dois caminhos vai
funcionar.

### Tamanho do VPS

O painel é pequeno: 38 cartórios mandando um relatório por dia dão cerca de
1.200 relatórios por mês, cada um com alguns KB. A menor máquina de qualquer
provedor dá conta com folga:

| | mínimo | confortável |
|---|---|---|
| CPU | 1 núcleo | 1 núcleo |
| Memória | 1 GB | 2 GB |
| Disco | 20 GB | 40 GB |

Não precisa ficar no Brasil, mas ficando a tela abre mais rápido.

---

## Receita

### 1. No VPS, instalar o Docker

```bash
curl -fsSL https://get.docker.com | sh
```

### 2. Apontar o domínio

No painel de controle do seu domínio, crie um registro **A**:

```
painel.seudominio.com.br  ->  IP DO VPS
```

Espere propagar. Para conferir, no VPS:

```bash
ping painel.seudominio.com.br
```

Tem de responder com o IP do VPS. Enquanto não responder, não siga: o
certificado vai falhar.

### 3. Liberar as portas 80 e 443

```bash
sudo ufw allow 80
sudo ufw allow 443
```

A **80 é obrigatória** mesmo que o painel só use HTTPS: é por ela que o
Let's Encrypt confirma que o domínio é seu.

### 4. Levar o código e editar o Caddyfile

Copie a pasta do painel para o VPS e edite o `Caddyfile`, trocando as duas
linhas do topo pelo seu domínio e seu e-mail.

### 5. Subir

```bash
docker compose -f docker-compose.producao.yml up -d --build
```

Na primeira subida o Caddy pede o certificado ao Let's Encrypt sozinho.
Demora alguns segundos. Depois disso ele renova sozinho, para sempre — não há
tarefa agendada para esquecer.

### 6. Definir a senha de administrador

```bash
docker compose -f docker-compose.producao.yml exec painel node dist/scripts/definir-senha.js
```

### 7. Conferir

Abra `https://painel.seudominio.com.br`. Tem de aparecer o cadeado.

---

## Depois de publicar

### Trocar a URL dos cartórios

O endereço que vai no `send-http-json-urls` de cada cartório passa a ser:

```
https://painel.seudominio.com.br/api/report/<token>
```

Para os que já estão instalados, o script de configuração em lote faz isso
pela rede, sem ir de máquina em máquina.

### Backup do banco do painel

O painel guarda o histórico de todos os cartórios num arquivo só. Ele fica no
volume `dados` do Docker. **Faça backup dele** — é o único lugar onde esse
histórico existe.

```bash
docker compose -f docker-compose.producao.yml exec painel \
  sh -c 'cat /dados/painel.db' > painel-$(date +%F).db
```

---

## O que muda em segurança quando isso vai para a internet

Hoje o painel só é alcançável de dentro. Publicando, ele passa a receber
visita de qualquer um. Três coisas deixam de ser opcionais:

**HTTPS.** O token de cada cartório viaja em cada relatório, e é ele que
autentica o cartório. Uma única requisição em texto aberto entrega o token, e
quem o tiver passa a poder mandar relatório falso em nome daquele cartório —
inclusive dizendo que o backup deu certo quando não deu. Por isso o painel
fica sem porta aberta neste arranjo: quem fala com a internet é o proxy.

**Senha de administrador nova.** A que está em uso hoje passou por conversa e
por terminal. Antes de publicar, defina outra.

**Bloqueio de tentativas.** Já existe: o painel conta as falhas de login por
IP e vai aumentando a espera. Atrás do proxy isso continua funcionando porque
o Express está configurado para confiar no `X-Forwarded-For`.

---

---

# Caminho B — máquina Linux da própria empresa

Mais barato e perfeitamente adequado: o painel é pequeno e não precisa de
datacenter. Só há um detalhe que decide tudo antes.

## Primeiro: você tem IP público de verdade?

Boa parte das operadoras no Brasil não entrega IP público em plano comum. O
cliente fica atrás do NAT da operadora (CGNAT) e **não existe porta para
redirecionar** — nenhuma configuração de roteador resolve.

Para descobrir, na máquina Linux:

```bash
curl -s ifconfig.me
```

Anote o resultado. Agora entre no roteador e veja o IP da porta WAN dele.

- **Os dois iguais** → você tem IP público. Pode abrir porta.
- **Diferentes** (o do roteador começa com `100.`, `10.` ou `192.168.`) →
  está em CGNAT. Abrir porta não vai funcionar.

## Se tem IP público

Siga a receita do Caminho A, com duas diferenças:

1. Redirecione as portas 80 e 443 do roteador para a máquina Linux.
2. Como o IP muda, use DNS dinâmico no seu provedor de domínio, senão os 38
   cartórios param de reportar quando o IP trocar de madrugada — e ninguém
   percebe até alguém abrir o painel.

## Se está em CGNAT (ou quer evitar abrir porta)

Use o túnel. A máquina liga **para fora** e o tráfego entra por dentro dessa
conexão:

```bash
docker compose -f docker-compose.tunel.yml up -d --build
```

Preparo:

1. Coloque o domínio na Cloudflare (o plano gratuito serve).
2. Em **Zero Trust → Networks → Tunnels**, crie um túnel e copie o token.
3. No túnel, aponte o hostname público para `http://painel:3000`.
4. Crie um arquivo `.env` ao lado do compose:
   ```
   TUNEL_TOKEN=cole-o-token-aqui
   ```

Esse arquivo já está no `.gitignore`. **O token não pode ir para a pasta de
entrega na rede** — quem o tiver publica o que quiser no seu domínio.

Vantagens além do CGNAT: não abre porta nenhuma na rede da empresa, o IP pode
mudar à vontade, e o certificado HTTPS fica com a Cloudflare — sem renovação
para esquecer.

## Cuidados de uma máquina no escritório

**Não pode dormir.** Um Linux de mesa costuma suspender sozinho:

```bash
sudo systemctl mask sleep.target suspend.target hibernate.target
```

**Tem que voltar sozinha depois de faltar luz.** No BIOS/UEFI, procure
*Restore on AC Power Loss* e deixe em *Power On*. Sem isso, uma queda de
energia num sábado deixa os 38 cartórios sem reportar até segunda.

**O Docker precisa subir no boot:**

```bash
sudo systemctl enable docker
```

O `restart: unless-stopped` do compose cuida do resto.

**Nobreak.** A máquina não guarda backup nenhum, mas guarda o histórico de
todos os cartórios — e é o único lugar onde ele existe.

## Backup do banco do painel

Vale para os dois caminhos, e é a parte que se esquece. Deixe rodando todo
dia:

```bash
0 2 * * * docker compose -f /caminho/docker-compose.tunel.yml exec -T painel \
  sh -c 'cat /dados/painel.db' > /backup/painel-$(date +\%F).db
```

E leve essa pasta para algum lugar fora da máquina.
