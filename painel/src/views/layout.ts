import { esc } from '../util/formato';

/**
 * O HTML base de todas as páginas.
 *
 * O CSS vai embutido na página, não num arquivo separado. Para um painel de
 * três telas isso é uma vantagem: nada de servir arquivo estático, nada de
 * cache desatualizado depois de uma alteração, e o visual inteiro fica num
 * lugar só quando você for mexer.
 */

const CSS = `
:root {
  /* Identidade CH.Com */
  --azul:        #00A8FF;
  --azul-claro:  #4CC3FF;
  --azul-escuro: #0079B8;
  --fundo:       #14161C;
  --superficie:  #1D2029;
  --superficie2: #232734;
  --borda:       #2B3040;
  --texto:       #E8EBF0;
  --texto2:      #C0C6D1;
  --texto3:      #8B93A3;

  /* Cores de estado. Não são decoração: dizem se o backup funcionou.
     Por isso ficam fora da paleta da marca. */
  --ok:     #22C55E;
  --aviso:  #F5A524;
  --erro:   #F3436B;
  --neutro: #6B7280;
}

* { box-sizing: border-box; }

body {
  margin: 0;
  background: var(--fundo);
  color: var(--texto);
  font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
  font-size: 15px;
  line-height: 1.5;
}

a { color: var(--azul); text-decoration: none; }
a:hover { color: var(--azul-claro); text-decoration: underline; }

.container { max-width: 1280px; margin: 0 auto; padding: 0 24px 64px; }

/* ---- cabeçalho ---------------------------------------------------------- */

header.topo {
  background: var(--superficie);
  border-bottom: 1px solid var(--borda);
  margin-bottom: 32px;
}

header.topo .interno {
  max-width: 1280px;
  margin: 0 auto;
  padding: 18px 24px;
  display: flex;
  align-items: center;
  gap: 14px;
  flex-wrap: wrap;
}

.marca {
  display: flex;
  align-items: center;
  gap: 11px;
  font-size: 18px;
  font-weight: 600;
  color: var(--texto);
}
.marca:hover { text-decoration: none; color: var(--texto); }

.marca .simbolo {
  width: 30px; height: 30px;
  border-radius: 7px;
  background: var(--azul);
  color: var(--fundo);
  display: grid;
  place-items: center;
  font-size: 13px;
  font-weight: 700;
  letter-spacing: -0.3px;
}

.marca .sub { color: var(--texto3); font-weight: 400; font-size: 14px; }

header.topo nav { margin-left: auto; display: flex; gap: 20px; font-size: 14px; }
header.topo nav a { color: var(--texto2); }
header.topo nav a:hover { color: var(--azul); }

/* ---- títulos ------------------------------------------------------------ */

h1 { font-size: 24px; font-weight: 600; margin: 0 0 4px; }
h2 { font-size: 17px; font-weight: 600; margin: 36px 0 14px; }
.legenda { color: var(--texto3); font-size: 14px; margin: 0 0 26px; }

.voltar { font-size: 14px; color: var(--texto3); display: inline-block; margin-bottom: 14px; }
.voltar:hover { color: var(--azul); }

/* ---- cartões de números ------------------------------------------------- */

.cartoes {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(190px, 1fr));
  gap: 14px;
  margin-bottom: 34px;
}

.cartao {
  background: var(--superficie);
  border: 1px solid var(--borda);
  border-radius: 10px;
  padding: 16px 18px;
}

.cartao .rotulo {
  color: var(--texto3);
  font-size: 12px;
  text-transform: uppercase;
  letter-spacing: 0.6px;
  margin-bottom: 7px;
}

.cartao .valor { font-size: 26px; font-weight: 600; line-height: 1.15; }
.cartao .valor.azul   { color: var(--azul); }
.cartao .valor.ok     { color: var(--ok); }
.cartao .valor.aviso  { color: var(--aviso); }
.cartao .valor.erro   { color: var(--erro); }
.cartao .valor.neutro { color: var(--texto3); }
.cartao .nota { color: var(--texto3); font-size: 13px; margin-top: 5px; }

/* ---- tabelas ------------------------------------------------------------ */

.tabela-area {
  background: var(--superficie);
  border: 1px solid var(--borda);
  border-radius: 10px;
  overflow-x: auto;   /* tabela larga rola sozinha, a página não */
}

table { width: 100%; border-collapse: collapse; font-size: 14px; }

thead th {
  text-align: left;
  padding: 12px 16px;
  color: var(--texto3);
  font-size: 12px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  border-bottom: 1px solid var(--borda);
  white-space: nowrap;
}

tbody td {
  padding: 13px 16px;
  border-bottom: 1px solid var(--borda);
  vertical-align: middle;
}

tbody tr:last-child td { border-bottom: none; }
tbody tr:hover { background: var(--superficie2); }

td.num, th.num { text-align: right; font-variant-numeric: tabular-nums; white-space: nowrap; }
td.fraco { color: var(--texto3); }

.nome-cartorio { font-weight: 600; color: var(--texto); }
.nome-cartorio:hover { color: var(--azul); }
.cidade { color: var(--texto3); font-size: 13px; }

/* ---- selo de situação ---------------------------------------------------
   O selo tem bolinha COLORIDA e TEXTO. Só a cor não basta: cerca de 8% dos
   homens têm alguma deficiência na visão de cores, e verde e vermelho são
   justamente o par mais afetado. */

.selo {
  display: inline-flex;
  align-items: center;
  gap: 7px;
  padding: 4px 11px 4px 9px;
  border-radius: 999px;
  font-size: 12.5px;
  font-weight: 600;
  white-space: nowrap;
}

.selo .ponto { width: 8px; height: 8px; border-radius: 50%; flex: none; }

.selo.ok        { background: rgba(34,197,94,.13);  color: var(--ok); }
.selo.ok .ponto { background: var(--ok); }
.selo.aviso        { background: rgba(245,165,36,.13); color: var(--aviso); }
.selo.aviso .ponto { background: var(--aviso); }
.selo.erro        { background: rgba(243,67,107,.13); color: var(--erro); }
.selo.erro .ponto { background: var(--erro); }
.selo.sem-dados        { background: rgba(107,114,128,.15); color: var(--texto3); }
.selo.sem-dados .ponto { background: var(--neutro); }

/* ---- barrinha proporcional na tabela ------------------------------------ */

.barra {
  height: 4px;
  background: var(--azul);
  border-radius: 2px;
  margin-top: 5px;
  min-width: 2px;
  opacity: .75;
}

/* ---- gráfico ------------------------------------------------------------ */

.grafico-area {
  background: var(--superficie);
  border: 1px solid var(--borda);
  border-radius: 10px;
  padding: 20px 22px;
  margin-bottom: 8px;
}

.grafico-area svg { display: block; width: 100%; height: auto; }

/* ---- vazio e avisos ------------------------------------------------------ */

.vazio {
  background: var(--superficie);
  border: 1px dashed var(--borda);
  border-radius: 10px;
  padding: 44px 24px;
  text-align: center;
  color: var(--texto3);
}

.vazio strong { color: var(--texto2); display: block; margin-bottom: 8px; font-size: 16px; }

code, .mono {
  font-family: 'Cascadia Mono', Consolas, monospace;
  font-size: 13px;
  background: var(--fundo);
  border: 1px solid var(--borda);
  border-radius: 5px;
  padding: 2px 7px;
  color: var(--azul);
  word-break: break-all;
}

.rodape {
  margin-top: 44px;
  padding-top: 18px;
  border-top: 1px solid var(--borda);
  color: var(--texto3);
  font-size: 13px;
}

@media (max-width: 640px) {
  .container { padding: 0 14px 44px; }
  header.topo .interno { padding: 14px; }
  h1 { font-size: 20px; }
}

/* ---- CH.Com Cofre -------------------------------------------------------- */

.subtitulo { color: var(--texto3); margin: -10px 0 26px; font-size: 14px; }

/* Texto de apoio acima de uma tabela: explica o que a coluna significa
   ANTES de a pessoa interpretar errado, e não num rodapé que ninguém lê. */
.ajuda {
  color: var(--texto3);
  font-size: 13.5px;
  line-height: 1.55;
  margin: -6px 0 16px;
  max-width: 76ch;
}
.ajuda strong { color: var(--texto2); }

/* O veredito: uma frase que resume a tela. Quem ler só isto e fechar a
   página já sabe o essencial — e esse é o objetivo, não um efeito colateral. */
.veredito {
  display: block;
  border-radius: 10px;
  padding: 18px 22px;
  margin: 0 0 16px;
  border-left: 4px solid var(--neutro);
  background: var(--superficie);
}
.veredito strong { display: block; font-size: 16px; margin-bottom: 5px; }
.veredito span   { color: var(--texto2); font-size: 13.5px; line-height: 1.5; }

.veredito.ok    { border-left-color: var(--ok);    background: #10241A; }
.veredito.ok strong    { color: var(--ok); }
.veredito.aviso { border-left-color: var(--aviso); background: #2A2113; }
.veredito.aviso strong { color: var(--aviso); }
.veredito.erro  { border-left-color: var(--erro);  background: #2A141C; }
.veredito.erro strong  { color: var(--erro); }

td.tipo     { color: var(--texto2); white-space: nowrap; }
td.nome     { font-weight: 500; }
td.maquina  { color: var(--texto3); white-space: nowrap; }

/* A consistência aparece em toda linha, mesmo quando está tudo certo:
   um item verde crash-consistent não é a mesma coisa que um item verde
   application-consistent, e esconder isso transforma duas coisas
   diferentes na mesma luz verde. */
td.consistencia         { color: var(--texto3); font-size: 13px; }
td.consistencia.atencao { color: var(--aviso); font-weight: 500; }

/* O link para a outra tela do mesmo cartório. */
.atalho-cofre {
  display: inline-block;
  margin: 0 0 20px;
  padding: 11px 18px;
  border: 1px solid var(--borda);
  border-radius: 8px;
  background: var(--superficie);
  color: var(--texto2);
  font-size: 14px;
  text-decoration: none;
}
.atalho-cofre:hover {
  border-color: var(--azul);
  color: var(--texto);
  text-decoration: none;
}
`;

const CSS_NAV = `
.sair {
  background: none; border: none; padding: 0;
  color: var(--texto3); font: inherit; font-size: 14px; cursor: pointer;
}
.sair:hover { color: var(--azul); }
.quem { color: var(--texto3); font-size: 13px; }
`;

export function pagina(opcoes: {
  titulo: string;
  corpo: string;
  /** Usuário logado. Quando ausente, o cabeçalho sai sem o bloco de sessão. */
  usuario?: string;
}): string {
  return `<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(opcoes.titulo)} — Painel Backup CH.Com</title>
<style>${CSS}${CSS_NAV}</style>
</head>
<body>

<header class="topo">
  <div class="interno">
    <a href="/" class="marca">
      <span class="simbolo">CH</span>
      <span>Painel Backup <span class="sub">CH.Com</span></span>
    </a>
    <nav>
      <a href="/">Painel</a>
      <a href="/cartorios">Cartórios</a>
      <a href="/calibracao">Calibração</a>
      ${
        opcoes.usuario
          ? `<span class="quem">${esc(opcoes.usuario)}</span>
             <form method="POST" action="/sair" style="display:inline">
               <button type="submit" class="sair">Sair</button>
             </form>`
          : ''
      }
    </nav>
  </div>
</header>

<div class="container">
${opcoes.corpo}
</div>

</body>
</html>`;
}
