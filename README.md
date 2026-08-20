# CH.Com Backup

> Backup em nuvem **monitorado** para cartórios — instalação em um clique no servidor do cliente e um painel só, com todos eles.
>
> *Self-hosted monitoring panel and one-click installer for Duplicati-based offsite backups across many client sites.*

Um provedor de TI que cuida de dezenas de cartórios tem o mesmo problema em todos: o backup roda de madrugada, ninguém olha, e a falha só aparece no dia em que alguém precisa restaurar. Este projeto ataca isso por dois lados — padroniza a instalação no servidor do cliente e junta o resultado de todos num painel.

---

## 🧩 As duas partes

| Parte | Onde roda | Para quê |
|---|---|---|
| **`cartorio/`** | no servidor de cada cliente | instala, configura e diagnostica o backup |
| **`painel/`** | numa máquina só, do provedor | recebe o relatório de todos e mostra quem falhou |

Cada servidor manda um relatório ao fim de cada execução. O painel guarda o histórico e responde a pergunta que importa: **algum cliente parou de fazer backup?**

## ✨ O que ele faz

- **Instalação em um clique** — o `INSTALAR.bat` instala o Duplicati se não houver, aplica a identidade visual e deixa o programa no ar.
- **Regras padronizadas** — cópia de arquivos abertos (VSS), filtros de lixo e tolerância a link instável, iguais em todos os clientes.
- **Detecta backup que PAROU** — a falha mais perigosa não é a que dá erro, é a que some. Um cliente cujo último relatório diz "sucesso" mas não reporta há três dias aparece como **parado**, não como verde.
- **Diagnóstico que resolve** — diz o que está errado, se o programa caiu sozinho (lendo o log do Windows) e se oferece para religar.
- **Histórico por versão** — quanto subiu, em quanto tempo, a que velocidade, e o texto do erro quando falha.
- **Arquivo morto na AWS** — receita pronta para guardar em S3 Glacier Deep Archive, com o procedimento de restauração escrito antes de precisar.

## 🧱 Stack

| Camada | Tecnologia |
|---|---|
| Painel | **Node.js 22** · **TypeScript** · **Express** · **SQLite** |
| Telas | HTML e CSS escritos à mão, sem framework de frontend |
| Servidor do cliente | **PowerShell 5.1** (o que já existe em qualquer Windows) |
| Motor de backup | **[Duplicati](https://duplicati.com)** (MIT) |
| Publicação | **Docker** · **Caddy** (HTTPS automático) |

Sem framework de frontend e sem biblioteca de gráficos de propósito: o painel precisa abrir rápido pela conexão de um cliente do interior, e continuar abrindo daqui a alguns anos sem nada para reconstruir.

---

## 🚀 Rodando o painel

Pré-requisitos: **Node 22+**.

```bash
git clone https://github.com/CauaSoft/chcom-backup.git
cd chcom-backup/painel
npm install
npm run build
npm run migrar            # cria o banco
npm run definir-senha     # gera a senha de administrador e mostra uma vez
npm start                 # http://localhost:3000
```

No painel, cadastre cada cliente. Ele devolve uma **URL com token** — é ela que vai no backup do servidor daquele cliente.

## 🖥️ Instalando num servidor de cliente

Leve a pasta `cartorio/` para o servidor e rode, nesta ordem:

```
INSTALAR.bat          instala o Duplicati (se preciso) e aplica a identidade
APLICAR-REGRAS.bat    liga VSS, filtros e tolerância a queda de link
DEFINIR-SENHA.bat     define uma senha de acesso que você conheça
```

Depois, na tela do backup, configure o destino e cole a URL que o painel gerou em `send-http-json-urls`.

Se algo não funcionar:

```
DIAGNOSTICO.bat       o que está instalado, se caiu, quando o backup rodou
CORRIGIR-S3.bat       conserta destinos gravados como "s3-aws://"
DESINSTALAR.bat       devolve o Duplicati ao original
```

## 🌐 Publicando o painel

Enquanto o painel só existe em `localhost`, os clientes **não conseguem** mandar relatório — o endereço é local, e `localhost` dentro do servidor do cliente aponta para ele mesmo.

Duas receitas prontas em [`docs/PUBLICAR-NA-INTERNET.md`](./docs/PUBLICAR-NA-INTERNET.md):

```bash
# VPS com IP público — Caddy pede e renova o certificado sozinho
docker compose -f docker-compose.producao.yml up -d --build

# Máquina própria atrás de CGNAT — túnel, sem abrir porta no roteador
docker compose -f docker-compose.tunel.yml up -d --build
```

Em qualquer um dos dois o painel fica **sem porta aberta**: quem fala com a internet é o proxy. O token de cada cliente viaja em cada relatório e é ele que autentica o cliente — uma requisição em texto aberto já o entrega.

---

## 📁 Estrutura

```
painel/          o painel (Node + TypeScript + SQLite)
  src/rotas/     recebimento de relatório, telas e login
  src/duplicati/ leitura do JSON que o Duplicati manda
  src/views/     o HTML de cada tela
cartorio/        o que roda no servidor do cliente (PowerShell)
marca/           identidade visual e os geradores do pacote
docs/            guias de publicação, restauração e AWS
```

## 📚 Documentação

| Arquivo | Assunto |
|---|---|
| [`docs/PUBLICAR-NA-INTERNET.md`](./docs/PUBLICAR-NA-INTERNET.md) | pôr o painel no ar, com HTTPS |
| [`docs/AWS-REGRA-DEEP-ARCHIVE.txt`](./docs/AWS-REGRA-DEEP-ARCHIVE.txt) | mover os dados para arquivo morto e o que isso custa |
| [`docs/RESTAURAR-DO-ARQUIVO-MORTO.txt`](./docs/RESTAURAR-DO-ARQUIVO-MORTO.txt) | restaurar de lá, passo a passo, com os tempos reais |
| [`docs/COMO-GERAR-O-INSTALADOR.md`](./docs/COMO-GERAR-O-INSTALADOR.md) | montar o pacote de instalação |

## ⚠️ O que este projeto não faz

- **Não substitui o Duplicati.** Ele padroniza, monitora e embala — o backup em si é do Duplicati.
- **Não testa restauração sozinho.** Quando os dados vão para arquivo morto, a conferência automática do backup precisa ser desligada (não se lê arquivo congelado). A prova de que o backup presta passa a ser um teste de restauração feito por gente, de tempos em tempos.
- **Não guarda a senha de criptografia dos backups.** Sem ela, os arquivos não abrem — nem para você, nem para ninguém. Ela vive no seu cofre de senhas.

## 📄 Licença

MIT — veja [LICENSE](./LICENSE).

Este projeto usa o [Duplicati](https://duplicati.com) (MIT) e **não é** um produto oficial dele. Detalhes em [NOTICE.md](./NOTICE.md).

O nome e o logotipo **CH.Com** não estão cobertos pela licença. Reaproveitando o código, troque-os pelos seus.
