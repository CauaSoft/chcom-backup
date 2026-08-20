import { bytes, dataCurta, esc } from '../util/formato';

/**
 * Gráfico de crescimento do backup, desenhado como SVG direto no servidor.
 *
 * Sem biblioteca de gráficos de propósito. Uma linha do tempo com um valor
 * por ponto é geometria simples, e trazer Chart.js ou D3 para isso custaria
 * centenas de kilobytes de JavaScript e mais uma dependência para manter —
 * num painel que precisa abrir rápido pela conexão de um cartório do
 * interior de Rondônia.
 *
 * O SVG é responsivo pelo viewBox: ele se ajusta à largura disponível sem
 * nenhum JavaScript.
 */

export interface PontoGrafico {
  /** Data em ISO 8601. */
  quando: string;
  valor: number;
}

/**
 * Os dois gráficos do painel, lado a lado.
 *
 * O primeiro responde "a operação rodou ontem?", o segundo "quanto de dado
 * está subindo?". São perguntas diferentes e nenhuma delas era respondida na
 * tela: a lista mostra o estado de cada cartório agora, e nada sobre o
 * conjunto ao longo do tempo.
 *
 * Feito em HTML e CSS, não em SVG. Um SVG com viewBox é esticado para a
 * largura disponível e a espessura da coluna passaria a depender do tamanho
 * da janela em vez da especificação. Em HTML, 14px são 14px.
 */
export interface DiaGrafico {
  dia: string;
  ok: number;
  aviso: number;
  erro: number;
  enviado: number;
}

export function graficosDoPainel(dias: DiaGrafico[]): string {
  if (dias.length < 2) {
    return `
  <div class="graficos">
    <div class="gcaixa vazia">
      Os gráficos aparecem a partir do segundo dia com backup recebido.
    </div>
  </div>`;
  }

  return `
  <div class="graficos">
    ${colunasExecucoes(dias)}
    ${colunasVolume(dias)}
  </div>
  ${CSS_GRAFICOS}`;
}

/** Execuções por dia, empilhadas por resultado. Falha embaixo, onde salta. */
function colunasExecucoes(dias: DiaGrafico[]): string {
  const totais = dias.map((d) => d.ok + d.aviso + d.erro);
  const topo = topoRedondo(Math.max(...totais, 1));
  const totalFalhas = dias.reduce((s, d) => s + d.erro, 0);

  const barras = dias
    .map((d) => {
      const total = d.ok + d.aviso + d.erro;
      const alturaTotal = (total / topo) * 100;
      // Cada pedaço em proporção ao total do dia, dentro da altura do dia.
      const parte = (n: number) => (total > 0 ? (n / total) * alturaTotal : 0);
      return `
      <div class="faixa" title="${esc(dataCurta(d.dia))}: ${total} execuç${
        total === 1 ? 'ão' : 'ões'
      }${d.erro > 0 ? `, ${d.erro} com falha` : ''}${d.aviso > 0 ? `, ${d.aviso} com aviso` : ''}">
        <div class="pilha">
          <div class="p ok"    style="height:${parte(d.ok).toFixed(1)}%"></div>
          <div class="p aviso" style="height:${parte(d.aviso).toFixed(1)}%"></div>
          <div class="p erro"  style="height:${parte(d.erro).toFixed(1)}%"></div>
        </div>
      </div>`;
    })
    .join('');

  return `
    <div class="gcaixa">
      <div class="gtopo">
        <span class="gtit">Execuções por dia</span>
        <span class="gleg">
          <span class="ch ok"></span>êxito
          <span class="ch aviso"></span>aviso
          <span class="ch erro"></span>falha
        </span>
      </div>
      <div class="plot">
        ${grade(topo, (v) => numeroCurto(v))}
        <div class="cols">${barras}</div>
      </div>
      <div class="eixo"><span>${esc(dataCurta(dias[0]!.dia))}</span>
        <span>${esc(dataCurta(dias[dias.length - 1]!.dia))}</span></div>
      <div class="gnota">${
        totalFalhas === 0
          ? 'nenhuma falha no período'
          : `${totalFalhas} falha${totalFalhas === 1 ? '' : 's'} no período`
      }</div>
    </div>`;
}

/** Volume enviado por dia. É a conta que vira dinheiro na AWS. */
function colunasVolume(dias: DiaGrafico[]): string {
  const valores = dias.map((d) => d.enviado);
  const maximo = Math.max(...valores);
  const total = valores.reduce((s, v) => s + v, 0);

  if (maximo <= 0) {
    return `
    <div class="gcaixa">
      <div class="gtopo"><span class="gtit">Enviado por dia</span></div>
      <div class="gvazio">nenhum envio medido no período</div>
    </div>`;
  }

  const topo = topoBytes(maximo);
  const barras = dias
    .map(
      (d) => `
      <div class="faixa" title="${esc(dataCurta(d.dia))}: ${esc(bytes(d.enviado))}">
        <div class="p azul" style="height:${Math.max(
          d.enviado > 0 ? 1.5 : 0,
          (d.enviado / topo) * 100,
        ).toFixed(1)}%"></div>
      </div>`,
    )
    .join('');

  return `
    <div class="gcaixa">
      <div class="gtopo">
        <span class="gtit">Enviado por dia</span>
        <span class="gleg">${esc(bytes(total))} no período</span>
      </div>
      <div class="plot">
        ${grade(topo, (v) => bytes(v))}
        <div class="cols">${barras}</div>
      </div>
      <div class="eixo"><span>${esc(dataCurta(dias[0]!.dia))}</span>
        <span>${esc(dataCurta(dias[dias.length - 1]!.dia))}</span></div>
      <div class="gnota">soma de todos os cartórios</div>
    </div>`;
}

function grade(topo: number, formatar: (v: number) => string): string {
  return (
    [1, 0.5]
      .map(
        (f) => `<div class="lin" style="bottom:${f * 100}%">
                  <span>${esc(formatar(topo * f))}</span></div>`,
      )
      .join('') + '<div class="lin base" style="bottom:0"></div>'
  );
}

/* Topo da escala num número redondo. Sem isso a grade marca "7" e "3,5", que
   não é número de coisa nenhuma para quem lê. */
function topoRedondo(maximo: number): number {
  const folga = maximo * 1.15;
  const potencia = Math.pow(10, Math.floor(Math.log10(folga)));
  for (const passo of [1, 2, 2.5, 5, 10]) {
    if (passo * potencia >= folga) return passo * potencia;
  }
  return folga;
}

function topoBytes(maximo: number): number {
  const folga = maximo * 1.1;
  const unidade = Math.pow(1024, Math.floor(Math.log(folga) / Math.log(1024)));
  for (const passo of [1, 2, 5, 10, 20, 50, 100, 200, 500, 1024]) {
    if (passo * unidade >= folga) return passo * unidade;
  }
  return folga;
}

function numeroCurto(v: number): string {
  const n = Math.round(v);
  return n.toLocaleString('pt-BR');
}

const CSS_GRAFICOS = `
  <style>
    .graficos { display:grid; grid-template-columns:1fr 1fr; gap:16px; margin-bottom:26px; }
    .gcaixa { background:var(--superficie); border:1px solid var(--borda);
              border-radius:10px; padding:16px 18px 14px; }
    .gcaixa.vazia, .gvazio { color:var(--texto3); font-size:13px; text-align:center; padding:28px 10px; }
    .gtopo { display:flex; align-items:baseline; justify-content:space-between;
             gap:12px; margin-bottom:14px; flex-wrap:wrap; }
    .gtit { color:var(--texto2); font-size:13px; font-weight:600; }
    .gleg { color:var(--texto3); font-size:11.5px; display:flex; align-items:center; gap:5px; }
    .ch { width:8px; height:8px; border-radius:2px; display:inline-block; margin-left:7px; }
    .ch.ok { background:var(--ok); } .ch.aviso { background:var(--aviso); } .ch.erro { background:var(--erro); }

    .plot { position:relative; height:120px; }
    /* grade: hairline sólida, um passo acima da superfície, recessiva */
    .lin { position:absolute; left:0; right:0; height:1px; background:#2B3040; }
    .lin span { position:absolute; left:0; bottom:3px; color:var(--texto3); font-size:10px; }
    .lin.base { background:#3A4152; }
    .cols { position:absolute; inset:0; display:flex; align-items:flex-end; gap:2px; }
    /* a faixa distribui o espaço; a coluna dentro dela tem largura fixa, então
       a espessura não muda com o tamanho da janela */
    .faixa { flex:1; height:100%; display:flex; align-items:flex-end;
             justify-content:center; cursor:default; }
    .pilha { width:100%; max-width:14px; height:100%; display:flex;
             flex-direction:column; justify-content:flex-end; }
    .p { width:100%; max-width:14px; }
    .pilha .p:first-child { border-radius:3px 3px 0 0; }
    .p.ok { background:var(--ok); opacity:.85; }
    .p.aviso { background:var(--aviso); }
    .p.erro { background:var(--erro); }
    .p.azul { background:var(--azul); opacity:.85; border-radius:3px 3px 0 0; }
    .faixa:hover .p { opacity:1; filter:brightness(1.25); }
    .eixo { display:flex; justify-content:space-between; color:var(--texto3);
            font-size:10px; margin-top:7px; }
    .gnota { color:var(--texto3); font-size:11.5px; margin-top:8px; }

    @media (max-width:860px) { .graficos { grid-template-columns:1fr; } }
  </style>`;

const L = 74; // margem esquerda, espaço para os rótulos de tamanho
const R = 16;
const T = 16;
const B = 30; // margem inferior, espaço para as datas
const LARGURA = 900;
const ALTURA = 240;

export function graficoCrescimento(
  pontos: PontoGrafico[],
  titulo: string,
): string {
  if (pontos.length < 2) {
    return `
  <div class="grafico-area">
    <div class="rotulo" style="color:var(--texto3);font-size:12px;text-transform:uppercase;letter-spacing:.6px;margin-bottom:10px">${esc(titulo)}</div>
    <p style="color:var(--texto3);margin:14px 0;text-align:center">
      O gráfico aparece a partir do segundo backup recebido.
    </p>
  </div>`;
  }

  // Ordem cronológica: o histórico vem do mais novo para o mais velho, mas o
  // gráfico precisa do contrário, senão a curva de crescimento aparece
  // descendo.
  const dados = [...pontos].sort(
    (a, b) => new Date(a.quando).getTime() - new Date(b.quando).getTime(),
  );

  const tempos = dados.map((p) => new Date(p.quando).getTime());
  const tMin = Math.min(...tempos);
  const tMax = Math.max(...tempos);
  const spanT = tMax - tMin || 1; // evita divisão por zero se tudo for do mesmo instante

  const valores = dados.map((p) => p.valor);
  const vMax = Math.max(...valores);

  // O eixo Y começa em zero, sempre. Cortar a base para "aproveitar melhor o
  // espaço" é a forma mais comum de um gráfico mentir: um crescimento de 1%
  // vira uma escalada dramática. Num painel usado para decidir se algo está
  // errado, isso custa caro.
  const topo = vMax > 0 ? vMax * 1.1 : 1;

  const x = (t: number) => L + ((t - tMin) / spanT) * (LARGURA - L - R);
  const y = (v: number) => T + (1 - v / topo) * (ALTURA - T - B);

  const coords = dados.map((p, i) => ({
    x: x(tempos[i]!),
    y: y(p.valor),
    valor: p.valor,
    quando: p.quando,
  }));

  const linha = coords.map((c) => `${c.x.toFixed(1)},${c.y.toFixed(1)}`).join(' ');

  const base = ALTURA - B;
  const area = `${L},${base} ${linha} ${coords[coords.length - 1]!.x.toFixed(1)},${base}`;

  // Grade horizontal em 4 níveis
  const niveis = [0, 0.25, 0.5, 0.75, 1].map((f) => {
    const v = topo * f;
    return { v, y: y(v) };
  });

  const grade = niveis
    .map(
      (n) => `
    <line x1="${L}" y1="${n.y.toFixed(1)}" x2="${LARGURA - R}" y2="${n.y.toFixed(1)}"
          stroke="#2B3040" stroke-width="1" />
    <text x="${L - 10}" y="${(n.y + 4).toFixed(1)}" text-anchor="end"
          fill="#8B93A3" font-size="11">${esc(bytes(n.v))}</text>`,
    )
    .join('');

  // Datas no eixo X: primeira, meio e última. Mais que isso vira uma parede
  // de texto sobreposto quando há muitos backups.
  const indicesData =
    dados.length > 2
      ? [0, Math.floor(dados.length / 2), dados.length - 1]
      : [0, dados.length - 1];

  const rotulosX = [...new Set(indicesData)]
    .map((i) => {
      const c = coords[i]!;
      const ancora = i === 0 ? 'start' : i === dados.length - 1 ? 'end' : 'middle';
      return `<text x="${c.x.toFixed(1)}" y="${ALTURA - 8}" text-anchor="${ancora}"
                    fill="#8B93A3" font-size="11">${esc(dataCurta(dados[i]!.quando))}</text>`;
    })
    .join('');

  // Bolinhas só quando há poucos pontos. Com 200 backups elas viram um borrão.
  const bolinhas =
    coords.length <= 40
      ? coords
          .map(
            (c) =>
              `<circle cx="${c.x.toFixed(1)}" cy="${c.y.toFixed(1)}" r="3"
                       fill="#14161C" stroke="#00A8FF" stroke-width="2">
                 <title>${esc(dataCurta(c.quando))} — ${esc(bytes(c.valor))}</title>
               </circle>`,
          )
          .join('')
      : '';

  return `
  <div class="grafico-area">
    <div style="color:var(--texto3);font-size:12px;text-transform:uppercase;letter-spacing:.6px;margin-bottom:12px">${esc(titulo)}</div>
    <svg viewBox="0 0 ${LARGURA} ${ALTURA}" preserveAspectRatio="xMidYMid meet" role="img"
         aria-label="${esc(titulo)}: de ${esc(bytes(dados[0]!.valor))} a ${esc(bytes(dados[dados.length - 1]!.valor))}">
      <defs>
        <linearGradient id="degradeArea" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%"   stop-color="#00A8FF" stop-opacity="0.28" />
          <stop offset="100%" stop-color="#00A8FF" stop-opacity="0.02" />
        </linearGradient>
      </defs>

      ${grade}

      <polygon points="${area}" fill="url(#degradeArea)" />
      <polyline points="${linha}" fill="none" stroke="#00A8FF" stroke-width="2"
                stroke-linejoin="round" stroke-linecap="round" />
      ${bolinhas}
      ${rotulosX}
    </svg>
  </div>`;
}
