# ============================================================================
# Painel Backup CH.Com
#
# Build em dois estágios. O primeiro instala TODAS as dependências e compila
# o TypeScript; o segundo leva só o JavaScript pronto e as dependências de
# produção. Isso mantém o TypeScript, o tsx e os @types fora da imagem final.
# ============================================================================

# ---- estágio 1: compilar ---------------------------------------------------
FROM node:22-bookworm-slim AS build

WORKDIR /app

# O better-sqlite3 é um módulo nativo. Ele publica binários prontos para as
# plataformas comuns, mas se não houver um para esta, o npm compila na hora —
# e para isso precisa de compilador C++ e Python. Sem estes pacotes, a
# instalação falharia com um erro de node-gyp difícil de entender.
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 make g++ \
    && rm -rf /var/lib/apt/lists/*

# Copiar só os manifestos antes do código faz o Docker reaproveitar a camada
# de dependências enquanto o package.json não mudar. Alterar um arquivo em
# src/ deixa de disparar um npm ci inteiro.
COPY package.json package-lock.json* ./
RUN npm ci

COPY tsconfig.json ./
COPY src ./src
RUN npm run build

# O schema.sql não é código TypeScript, então o tsc não o copia para dist/.
# Sem esta linha, o container sobe e quebra na primeira consulta.
RUN cp src/db/schema.sql dist/db/schema.sql


# ---- estágio 2: imagem final -----------------------------------------------
FROM node:22-bookworm-slim AS producao

WORKDIR /app
ENV NODE_ENV=production

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 make g++ \
    && rm -rf /var/lib/apt/lists/*

COPY package.json package-lock.json* ./
RUN npm ci --omit=dev && npm cache clean --force

# Remove o compilador depois de instalar: ele só era necessário caso o
# better-sqlite3 precisasse ser compilado, e deixá-lo na imagem final
# aumentaria o tamanho e a superfície de ataque sem nenhum benefício.
RUN apt-get purge -y make g++ && apt-get autoremove -y

COPY --from=build /app/dist ./dist

# O banco fica num volume, fora da imagem. Se ficasse dentro, todo
# `docker compose up --build` apagaria o histórico de backups dos cartórios.
RUN mkdir -p /dados && chown -R node:node /dados /app
ENV DB_PATH=/dados/painel.db

# Rodar como usuário sem privilégios. A imagem do Node já traz o usuário
# `node` pronto para isso.
USER node

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://localhost:3000/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "dist/index.js"]
