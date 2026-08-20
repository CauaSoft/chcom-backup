import type { DiagnosticoCampo } from '../duplicati/parse';
import { dataHora, esc, numero } from '../util/formato';
import { pagina } from './layout';

export interface ItemCalibracao {
  id: number;
  cliente: string;
  recebidoEm: string;
  diagnostico: DiagnosticoCampo[];
  naoEncontrados: string[];
  jsonBruto: string;
  erroLeitura: string | null;
}

export interface ItemRecusa {
  recebido_em: string;
  motivo: string;
  token_usado: string | null;
  ip_origem: string | null;
}

/**
 * Tela de calibração: mostra o que chegou de verdade e como o parser leu
 * cada campo, lado a lado.
 *
 * É a tela para usar ao ligar um Duplicati novo: dispara um backup de teste,
 * abre aqui e confere campo a campo. O diagnóstico é recalculado na hora a
 * partir do JSON bruto guardado, então dá para corrigir o parser e recarregar
 * a página para ver o efeito — sem precisar rodar outro backup.
 *
 * O QUE MUDOU, E POR QUÊ
 *
 * Antes era preciso abrir os dez relatórios um a um e comparar de cabeça para
 * responder a única pergunta que a tela existe para responder: "tem algum
 * campo que este Duplicati não está mandando?". Agora esse resumo vem primeiro
 * e os relatórios ficam abaixo, como prova.
 */

/**
 * Nem todo campo pesa o mesmo.
 *
 * Sem `resultado` ou `fimEm` o painel não sabe dizer se o backup deu certo nem
 * quando foi — o cartório fica inútil na lista. Já `maquinaNome` faltando não
 * atrapalha nada. Tratar os treze como iguais faz um Duplicati perfeitamente
 * saudável parecer quebrado por causa de um campo decorativo.
 */
const ESSENCIAIS = new Set([
  'resultado',
  'fimEm',
  'duracaoSegundos',
  'tamanhoOrigem',
  'tamanhoDestino',
  'bytesEnviados',
]);

const ROTULO_CAMPO: Record<string, string> = {
  resultado: 'Resultado',
  operacao: 'Operação',
  backupNome: 'Nome do backup',
  maquinaNome: 'Nome da máquina',
  inicioEm: 'Início',
  fimEm: 'Fim',
  duracaoSegundos: 'Duração',
  tamanhoOrigem: 'Tamanho da origem',
  tamanhoAdicionado: 'Adicionado',
  bytesEnviados: 'Enviado',
  tamanhoDestino: 'Total no destino',
  qtdAvisos: 'Qtd. de avisos',
  qtdErros: 'Qtd. de erros',
};

export function telaCalibracao(opcoes: {
  itens: ItemCalibracao[];
  recusas: ItemRecusa[];
  usuario?: string;
}): string {
  const { itens, recusas } = opcoes;

  const corpo = `
  <h1>Calibração</h1>
  <p class="legenda">
    Confere se o painel está lendo todos os campos que o Duplicati manda.
    Use ao ligar um cartório novo: rode um backup de teste e confira aqui.
  </p>

  ${resumo(itens)}

  ${blocoRecusas(recusas)}

  <h2>Relatórios recebidos</h2>
  <p class="legenda">Os ${itens.length === 1 ? 'último' : `${numero(itens.length)} últimos`}
     que chegaram, do mais recente para o mais antigo. Abra um para ver campo a campo.</p>

  ${
    itens.length === 0
      ? `<div class="vazio"><strong>Nenhum relatório recebido ainda</strong>
         <p>Configure o <code>send-http-json-urls</code> num Duplicati e rode um backup.</p></div>`
      : itens.map(bloco).join('\n')
  }

  ${CSS}`;

  return pagina({ titulo: 'Calibração', corpo, usuario: opcoes.usuario });
}

/**
 * O resumo que responde a pergunta da tela numa olhada: quais campos faltaram,
 * em quantos dos relatórios analisados.
 */
function resumo(itens: ItemCalibracao[]): string {
  const legiveis = itens.filter((i) => !i.erroLeitura);
  if (legiveis.length === 0) return '';

  // Quantos relatórios deixaram de trazer cada campo.
  const faltasPorCampo = new Map<string, number>();
  for (const item of legiveis) {
    for (const campo of item.naoEncontrados) {
      faltasPorCampo.set(campo, (faltasPorCampo.get(campo) ?? 0) + 1);
    }
  }

  // O total de campos vem do próprio diagnóstico, nunca de um número escrito
  // à mão: o parser ganha campos com o tempo, e um número fixo aqui passa a
  // mentir sem ninguém perceber. Já mentia — dizia 11 quando havia 13.
  const totalCampos = legiveis[0]?.diagnostico.length ?? 0;

  if (faltasPorCampo.size === 0) {
    return `
  <div class="faixa tudo-ok">
    <span class="ic">&#10003;</span>
    <div>
      <strong>Todos os ${numero(totalCampos)} campos foram lidos</strong>
      <span>nos ${numero(legiveis.length)} relatórios analisados — nada a calibrar</span>
    </div>
  </div>`;
  }

  const faltas = [...faltasPorCampo.entries()].sort((a, b) => {
    const ea = ESSENCIAIS.has(a[0]) ? 0 : 1;
    const eb = ESSENCIAIS.has(b[0]) ? 0 : 1;
    if (ea !== eb) return ea - eb;
    return b[1] - a[1];
  });

  const temEssencial = faltas.some(([campo]) => ESSENCIAIS.has(campo));

  return `
  <div class="faixa ${temEssencial ? 'grave' : 'atencao'}">
    <span class="ic">${temEssencial ? '&#10007;' : '&#33;'}</span>
    <div>
      <strong>${numero(faltas.length)} campo${faltas.length === 1 ? '' : 's'} não ${
        faltas.length === 1 ? 'chegou' : 'chegaram'
      } em algum relatório</strong>
      <span>${
        temEssencial
          ? 'há campo essencial faltando — o painel mostra dado incompleto para este cartório'
          : 'nenhum deles é essencial; o painel funciona sem eles'
      }</span>
    </div>
  </div>

  <div class="tabela-area" style="margin-bottom:30px">
    <table class="tb-resumo">
      <thead>
        <tr>
          <th>Campo que faltou</th>
          <th>Peso</th>
          <th class="num">Em quantos relatórios</th>
        </tr>
      </thead>
      <tbody>
        ${faltas
          .map(
            ([campo, n]) => `
        <tr>
          <td><strong>${esc(ROTULO_CAMPO[campo] ?? campo)}</strong>
              <span class="chave">${esc(campo)}</span></td>
          <td>${
            ESSENCIAIS.has(campo)
              ? '<span class="peso essencial">essencial</span>'
              : '<span class="peso extra">complementar</span>'
          }</td>
          <td class="num">${numero(n)} de ${numero(legiveis.length)}</td>
        </tr>`,
          )
          .join('')}
      </tbody>
    </table>
  </div>`;
}

/**
 * Recebimentos recusados. A seção aparece SEMPRE, inclusive vazia: quando um
 * cartório configurado não dá sinal, a primeira coisa a saber é se algo
 * chegou e foi rejeitado ou se não chegou nada. "Nenhuma recusa" é resposta,
 * e esconder a seção deixava a pergunta sem resposta.
 */
function blocoRecusas(recusas: ItemRecusa[]): string {
  if (recusas.length === 0) {
    return `
  <h2>Recebimentos recusados</h2>
  <p class="legenda vazio-linha">Nenhum. Tudo que chegou ao painel foi aceito.
     Se um cartório configurado não aparece na lista, então nada saiu da
     máquina dele — confira o <code>send-http-json-urls</code> lá.</p>`;
  }

  return `
  <h2>Recebimentos recusados</h2>
  <p class="legenda">Chegaram ao painel mas não foram gravados. Se um cartório
     configurado não aparece, a explicação costuma estar aqui.</p>
  <div class="tabela-area" style="margin-bottom:34px">
    <table>
      <thead><tr><th>Quando</th><th>Motivo</th><th>Token usado</th><th>IP</th></tr></thead>
      <tbody>
        ${recusas
          .map(
            (r) => `
        <tr>
          <td style="white-space:nowrap">${esc(dataHora(r.recebido_em))}</td>
          <td class="motivo">${esc(r.motivo)}</td>
          <td class="fraco"><code style="font-size:12px">${esc(r.token_usado ?? '—')}</code></td>
          <td class="fraco">${esc(r.ip_origem ?? '—')}</td>
        </tr>`,
          )
          .join('')}
      </tbody>
    </table>
  </div>`;
}

function bloco(item: ItemCalibracao): string {
  const total = item.diagnostico.length;
  const faltando = item.naoEncontrados.length;
  const faltaEssencial = item.naoEncontrados.some((c) => ESSENCIAIS.has(c));

  const aviso = item.erroLeitura
    ? '<span class="selo erro"><span class="ponto"></span>JSON ilegível</span>'
    : faltando === 0
      ? `<span class="selo ok"><span class="ponto"></span>${total} de ${total} campos lidos</span>`
      : `<span class="selo ${faltaEssencial ? 'erro' : 'aviso'}"><span class="ponto"></span>${
          total - faltando
        } de ${total} campos lidos</span>`;

  return `
  <details class="rel"${faltando > 0 || item.erroLeitura ? ' open' : ''}>
    <summary>
      <strong>#${item.id}</strong>
      <span>${esc(item.cliente)}</span>
      <span class="cidade">${esc(dataHora(item.recebidoEm))}</span>
      <span style="margin-left:auto">${aviso}</span>
    </summary>
    <div class="interno">
      ${
        item.erroLeitura
          ? `<p style="color:var(--erro)">O JSON guardado não pôde ser lido: ${esc(item.erroLeitura)}</p>`
          : `
      <table class="dtab">
        <thead>
          <tr><th>Campo</th><th>Onde foi achado no JSON</th><th>Valor bruto</th><th>Valor lido</th></tr>
        </thead>
        <tbody>
          ${item.diagnostico.map(linhaDiag).join('')}
        </tbody>
      </table>`
      }

      <details class="bruto-caixa">
        <summary>JSON bruto recebido &middot;
          <span class="fraco">${esc(tamanhoLegivel(item.jsonBruto.length))}</span></summary>
        <pre class="bruto">${esc(recortar(item.jsonBruto))}</pre>
      </details>
    </div>
  </details>`;
}

/**
 * O JSON bruto fica fechado por padrão e recortado.
 *
 * Um relatório de backup que encontrou milhares de arquivos travados passa de
 * vários MB. Dez deles abertos na mesma página travavam o navegador — e nunca
 * foi o JSON inteiro que alguém precisou ler, e sim o começo dele.
 */
const LIMITE_BRUTO = 20000;

function recortar(texto: string): string {
  if (texto.length <= LIMITE_BRUTO) return texto;
  return (
    texto.slice(0, LIMITE_BRUTO) +
    `\n\n[... recortado: mais ${(texto.length - LIMITE_BRUTO).toLocaleString('pt-BR')} caracteres.` +
    ` O relatório inteiro está guardado no banco.]`
  );
}

function tamanhoLegivel(n: number): string {
  if (n < 1024) return `${n} caracteres`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1).replace('.', ',')} KB`;
  return `${(n / 1024 / 1024).toFixed(1).replace('.', ',')} MB`;
}

function linhaDiag(d: DiagnosticoCampo): string {
  const achou = d.caminhoEncontrado !== null;
  const essencial = ESSENCIAIS.has(d.campo as string);
  return `
          <tr class="${achou ? '' : essencial ? 'falta-grave' : 'falta-leve'}">
            <td>
              <strong>${esc(ROTULO_CAMPO[d.campo as string] ?? d.campo)}</strong>
              <span class="chave">${esc(d.campo)}</span>
            </td>
            <td class="caminho ${achou ? '' : 'faltando'}">${
              achou ? esc(d.caminhoEncontrado) : 'não veio no JSON'
            }</td>
            <td class="valor fraco">${esc(formatarValor(d.valorBruto))}</td>
            <td class="valor">${esc(formatarValor(d.valorConvertido))}</td>
          </tr>`;
}

function formatarValor(v: unknown): string {
  if (v === null || v === undefined) return '—';
  if (typeof v === 'object') return JSON.stringify(v);
  return String(v);
}

const CSS = `
  <style>
    /* a faixa de resumo, igual à da tela principal: uma frase, não números */
    .faixa { display:flex; gap:14px; align-items:flex-start; padding:15px 18px;
             border-radius:10px; margin:20px 0 22px; border:1px solid transparent; }
    .faixa .ic { width:26px; height:26px; border-radius:50%; flex:none; display:flex;
                 align-items:center; justify-content:center; font-weight:700; font-size:14px; }
    .faixa strong { display:block; font-size:15px; margin-bottom:3px; }
    .faixa span:not(.ic) { font-size:13px; color:var(--texto2); line-height:1.6; }
    .faixa.tudo-ok { background:rgba(34,197,94,.07); border-color:rgba(34,197,94,.22); }
    .faixa.tudo-ok .ic { background:rgba(34,197,94,.16); color:var(--ok); }
    .faixa.tudo-ok strong { color:var(--ok); }
    .faixa.atencao { background:rgba(245,165,36,.07); border-color:rgba(245,165,36,.24); }
    .faixa.atencao .ic { background:rgba(245,165,36,.16); color:var(--aviso); }
    .faixa.atencao strong { color:var(--aviso); }
    .faixa.grave { background:rgba(243,67,107,.07); border-color:rgba(243,67,107,.26); }
    .faixa.grave .ic { background:rgba(243,67,107,.16); color:var(--erro); }
    .faixa.grave strong { color:var(--erro); }

    .tb-resumo { width:100%; border-collapse:collapse; font-size:13.5px; }
    .tb-resumo th { color:var(--texto3); font-size:11.5px; font-weight:500; text-align:left;
                    padding:0 14px 8px 0; border-bottom:1px solid var(--borda); }
    .tb-resumo th.num, .tb-resumo td.num { text-align:right; font-variant-numeric:tabular-nums; }
    .tb-resumo td { padding:10px 14px 10px 0; border-top:1px solid #23272F; }
    .peso { border-radius:999px; padding:2px 10px; font-size:11.5px; font-weight:600; }
    .peso.essencial { background:rgba(243,67,107,.14); color:var(--erro); }
    .peso.extra     { background:#232734; color:var(--texto3); }

    .vazio-linha { color:var(--texto3); }
    .motivo { color:var(--erro); }

    details.rel { background:var(--superficie); border:1px solid var(--borda);
                  border-radius:10px; margin-bottom:12px; }
    details.rel > summary {
      padding:14px 18px; cursor:pointer; list-style:none;
      display:flex; align-items:center; gap:12px; flex-wrap:wrap;
    }
    details.rel > summary::-webkit-details-marker { display:none; }
    details.rel > summary::before { content:'▸'; color:var(--texto3); }
    details.rel[open] > summary::before { content:'▾'; }
    details.rel > summary:hover { background:var(--superficie2); border-radius:10px; }
    details.rel .interno { padding:0 18px 18px; }

    .dtab { width:100%; border-collapse:collapse; font-size:13px; margin-bottom:14px; }
    .dtab th { text-align:left; padding:8px 10px; color:var(--texto3);
               font-size:11px; text-transform:uppercase; letter-spacing:.5px;
               border-bottom:1px solid var(--borda); }
    .dtab td { padding:7px 10px; border-bottom:1px solid var(--borda);
               vertical-align:top; word-break:break-word; }
    .dtab tr:last-child td { border-bottom:none; }
    .dtab .chave { color:var(--texto3); font-size:11px; margin-left:7px;
                   font-family:'Cascadia Mono',Consolas,monospace; }
    /* o caminho no JSON é código, não um dado destacado: tom de texto
       secundário em monoespaçada, e não a cor da marca */
    .dtab .caminho { font-family:'Cascadia Mono',Consolas,monospace; font-size:12px;
                     color:var(--texto2); }
    .dtab .faltando { color:var(--erro); font-weight:600; }
    .dtab .valor { font-family:'Cascadia Mono',Consolas,monospace; font-size:12px; }
    /* a linha inteira marcada na lateral: com 13 campos, achar a que faltou
       lendo coluna por coluna é trabalho desnecessário */
    .dtab tr.falta-grave td:first-child { box-shadow:inset 3px 0 0 var(--erro); }
    .dtab tr.falta-leve  td:first-child { box-shadow:inset 3px 0 0 var(--texto3); }

    details.bruto-caixa > summary {
      cursor:pointer; color:var(--texto3); font-size:12px;
      text-transform:uppercase; letter-spacing:.5px; padding:6px 0;
    }
    pre.bruto {
      background:var(--fundo); border:1px solid var(--borda); border-radius:8px;
      padding:14px; overflow-x:auto; font-size:12px; color:var(--texto2);
      font-family:'Cascadia Mono',Consolas,monospace; max-height:420px; margin:8px 0 0;
    }
  </style>`;
