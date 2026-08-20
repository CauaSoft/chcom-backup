import type { DiaResumo, LinhaPainel, PontoMini } from '../db/repo';
import { graficosDoPainel } from './grafico';
import {
  atrasoDe,
  bytes,
  dataHora,
  duracao,
  esc,
  HORAS_ATRASADO,
  HORAS_PARADO,
  numero,
  ROTULO_ATRASO,
  ROTULO_SITUACAO,
  situacaoDe,
  tempoDesde,
  type Atraso,
  type Situacao,
} from '../util/formato';
import { pagina } from './layout';

/**
 * A tela principal: um cartório por linha.
 *
 * COMO ELA FOI PENSADA
 *
 * Quem abre isto não quer ler 100 linhas: quer saber se precisa levantar da
 * cadeira. Então a tela responde nesta ordem:
 *
 *   1. "Preciso fazer alguma coisa agora?"  -> a faixa do topo
 *   2. "Qual cartório?"                     -> a lista, com os piores em cima
 *   3. "O que houve com ele?"               -> clicar na linha
 *
 * Duas decisões que vêm disso:
 *
 * - A lista chega ordenada por GRAVIDADE, não por nome. Com 100 cartórios,
 *   ordem alfabética esconde o problema no meio da página.
 * - As quatro caixas de contagem que existiam antes viraram uma faixa só. Com
 *   tudo certo elas mostravam quatro zeros e um "1": muito espaço para dizer
 *   "está tudo bem", que é a informação menos importante da tela.
 */

interface Avaliada {
  l: LinhaPainel;
  sit: Situacao;
  atraso: Atraso;
  /** Menor é pior. Define a ordem da lista. */
  peso: number;
  precisaAtencao: boolean;
}

function avaliar(l: LinhaPainel): Avaliada {
  const sit = situacaoDe(l.resultado);
  const quando = l.fim_em ?? l.recebido_em;
  const atraso = atrasoDe(quando);

  // Cartório desativado não entra na conta de problema: ele parou de propósito.
  const inativo = !l.ativo;

  let peso = 90;
  if (inativo) peso = 95;
  else if (atraso === 'nunca') peso = 20;
  else if (sit === 'erro') peso = 0;
  else if (atraso === 'parado') peso = 10;
  else if (atraso === 'atrasado') peso = 30;
  else if (sit === 'aviso') peso = 40;

  return { l, sit, atraso, peso, precisaAtencao: !inativo && peso < 90 };
}

/**
 * Minigráfico: as últimas execuções do cartório, uma coluna por execução,
 * altura = quanto subiu.
 *
 * É a diferença entre saber o ESTADO e saber o COMPORTAMENTO. Sem ele, um
 * cartório que falha dia sim dia não fica idêntico na lista a um que nunca
 * falhou — a diferença só aparece abrindo o histórico de cada um.
 *
 * Feito com divs e não com SVG: um SVG com viewBox é esticado para a largura
 * disponível, e a espessura da coluna passaria a depender do tamanho da
 * janela em vez da especificação. Em HTML, 3px são 3px.
 */
function mini(pontos: PontoMini[] | undefined): string {
  if (!pontos || pontos.length < 2) return '<span class="mini-vazio">&mdash;</span>';

  const valores = pontos.map((p) => p.bytes_enviados ?? 0);
  const topo = Math.max(...valores);

  // Sem nenhum valor medido, o gráfico sairia como uma fileira de tocos
  // todos do mesmo tamanho — o que PARECE dado, e dado nenhum é. Um traço é
  // honesto: não sabemos.
  if (topo <= 0) return '<span class="mini-vazio" title="sem medida de envio">&mdash;</span>';

  const colunas = pontos
    .map((p) => {
      const v = p.bytes_enviados ?? 0;
      const alt = Math.max(12, Math.round((v / topo) * 100));
      const s = situacaoDe(p.resultado);
      const cor = s === 'erro' ? 'err' : s === 'aviso' ? 'avi' : '';
      const q = p.fim_em ?? p.recebido_em;
      return `<i class="${cor}" style="height:${alt}%" title="${esc(
        dataHora(q) + ' — ' + bytes(p.bytes_enviados),
      )}"></i>`;
    })
    .join('');

  return `<span class="mini" aria-label="Últimas ${pontos.length} execuções">${colunas}</span>`;
}

export function telaPainel(
  linhas: LinhaPainel[],
  historico?: Map<number, PontoMini[]>,
  porDia?: DiaResumo[],
  usuario?: string,
): string {
  if (linhas.length === 0) return pagina({ titulo: 'Painel', corpo: vazio(), usuario });

  const avaliadas = linhas.map(avaliar).sort((a, b) => {
    if (a.peso !== b.peso) return a.peso - b.peso;
    return a.l.nome.localeCompare(b.l.nome, 'pt-BR');
  });

  const total = avaliadas.length;
  const atencao = avaliadas.filter((a) => a.precisaAtencao);

  let somaDestino = 0;
  for (const { l } of avaliadas) {
    // Soma o último valor CONHECIDO, não o do último relatório: um cartório
    // cujo backup de hoje falhou reporta 0, e somar esse 0 faria o total
    // guardado da CH.Com inteira despencar por causa de uma falha pontual.
    if (l.destino_conhecido) somaDestino += l.destino_conhecido;
  }

  const corpo = `
  <div class="topo-tela">
    <div>
      <h1>Cartórios</h1>
      <p class="legenda">${numero(total)} monitorado${total === 1 ? '' : 's'}
         &middot; ${esc(bytes(somaDestino))} guardados ao todo
         &middot; <span id="relogio" class="relogio">atualizado agora</span></p>
    </div>
    <button type="button" id="btn-atualizar" title="Atualizar agora">&#8635; Atualizar</button>
  </div>

  ${faixa(atencao, total)}

  ${graficosDoPainel(porDia ?? [])}

  <div class="ferramentas">
    <input type="search" id="busca" placeholder="Buscar cartório ou cidade&hellip;"
           autocomplete="off" spellcheck="false">
    <div class="filtros" role="group" aria-label="Filtrar por situação">
      <button type="button" class="fil ativo" data-fil="todos">Todos <span>${numero(total)}</span></button>
      <button type="button" class="fil" data-fil="atencao">Pedindo atenção <span>${numero(atencao.length)}</span></button>
    </div>
  </div>

  <div class="tabela-area">
    <table id="tabela">
      <thead>
        <tr>
          <th data-ord="nome">Cartório</th>
          <th data-ord="situacao">Situação</th>
          <th data-ord="quando">Último backup</th>
          <th class="col-mini">Últimas execuções</th>
          <th class="num" data-ord="duracao">Duração</th>
          <th class="num" data-ord="origem">Origem</th>
          <th class="num" data-ord="destino">Na nuvem</th>
          <th class="col-seta"></th>
        </tr>
      </thead>
      <tbody>
        ${avaliadas.map((a) => linha(a, historico?.get(a.l.id))).join('\n')}
      </tbody>
    </table>
    <div class="sem-resultado" id="sem-resultado" hidden>
      Nenhum cartório com esse nome.
    </div>
  </div>

  <p class="rodape">
    <strong>Origem</strong> é o tamanho examinado no servidor do cartório &middot;
    <strong>Na nuvem</strong> é o total já guardado na AWS &middot;
    <strong>atrasado</strong> após ${HORAS_ATRASADO} h sem reportar,
    <strong>parado</strong> após ${HORAS_PARADO} h — mesmo que o último
    relatório tenha dado certo.
  </p>

  ${estilo()}
  ${script()}`;

  return pagina({ titulo: 'Painel', corpo, usuario });
}

/**
 * A faixa do topo. Ou ela diz "está tudo em ordem" numa linha, ou nomeia quem
 * precisa de atenção. Nunca as duas coisas, e nunca uma parede de números.
 */
function faixa(atencao: Avaliada[], total: number): string {
  if (atencao.length === 0) {
    return `
  <div class="faixa tudo-ok">
    <span class="ic">&#10003;</span>
    <div>
      <strong>Tudo em ordem</strong>
      <span>os ${numero(total)} cartórios fizeram backup e reportaram no prazo</span>
    </div>
  </div>`;
  }

  const piores = atencao.slice(0, 4);
  const grave = atencao.some((a) => a.peso <= 10);

  return `
  <div class="faixa ${grave ? 'grave' : 'atencao'}">
    <span class="ic">${grave ? '&#10007;' : '&#33;'}</span>
    <div>
      <strong>${numero(atencao.length)} cartório${atencao.length === 1 ? '' : 's'} pedindo atenção</strong>
      <span>${piores
        .map(
          (a) =>
            `<a href="/cartorio/${a.l.id}">${esc(a.l.nome)}</a> <em>${esc(motivo(a))}</em>`,
        )
        .join(' &middot; ')}${atencao.length > piores.length ? ` &middot; e mais ${numero(atencao.length - piores.length)}` : ''}</span>
    </div>
  </div>`;
}

function motivo(a: Avaliada): string {
  if (a.atraso === 'nunca') return 'nunca reportou';
  if (a.sit === 'erro') return 'falhou';
  if (a.atraso === 'parado') return 'parado';
  if (a.atraso === 'atrasado') return 'atrasado';
  return 'com avisos';
}

function linha(a: Avaliada, pontos?: PontoMini[]): string {
  const { l, sit, atraso } = a;
  const inativo = !l.ativo;
  const quandoIso = l.fim_em ?? l.recebido_em;

  // Quem nunca reportou não tem "há quanto tempo" nem métrica nenhuma —
  // mostrar 0 B aqui pareceria um backup vazio, que é bem diferente de
  // ausência de informação.
  const quando =
    quandoIso === null
      ? '<span class="fraco">—</span>'
      : `${esc(dataHora(quandoIso))}<div class="cidade ${
          atraso === 'em-dia' ? '' : `alerta-${atraso}`
        }">${esc(tempoDesde(quandoIso))}</div>`;

  // O selo carrega ícone + palavra além da cor: quem não distingue verde de
  // amarelo lê o símbolo. E quando o backup deu certo mas parou de chegar,
  // é o ATRASO que manda na etiqueta — senão a linha fica verde mentindo.
  const mandaOAtraso = !inativo && sit === 'ok' && (atraso === 'atrasado' || atraso === 'parado');
  const classeSelo = mandaOAtraso ? (atraso === 'parado' ? 'erro' : 'aviso') : sit;
  const textoSelo = mandaOAtraso ? ROTULO_ATRASO[atraso] : ROTULO_SITUACAO[sit];

  const contadores = [
    l.qtd_erros ? `<span class="pas erro">${numero(l.qtd_erros)} erro${l.qtd_erros === 1 ? '' : 's'}</span>` : '',
    l.qtd_avisos ? `<span class="pas aviso">${numero(l.qtd_avisos)} aviso${l.qtd_avisos === 1 ? '' : 's'}</span>` : '',
  ].join('');

  return `
        <tr class="ln${a.precisaAtencao ? ' atencao' : ''}${inativo ? ' inativo' : ''}"
            data-ir="/cartorio/${l.id}"
            data-busca="${esc((l.nome + ' ' + l.cidade).toLowerCase())}"
            data-atencao="${a.precisaAtencao ? '1' : '0'}"
            data-nome="${esc(l.nome.toLowerCase())}"
            data-situacao="${a.peso}"
            data-quando="${quandoIso ? new Date(quandoIso).getTime() : 0}"
            data-duracao="${l.duracao_segundos ?? -1}"
            data-origem="${l.origem_conhecida ?? -1}"
            data-destino="${l.destino_conhecido ?? -1}">
          <td>
            <a href="/cartorio/${l.id}" class="nome-cartorio">${esc(l.nome)}</a>
            ${inativo ? '<span class="cidade"> &middot; desativado</span>' : ''}
            <div class="cidade">${esc(l.cidade)}</div>
          </td>
          <td>
            <span class="selo ${classeSelo}"><span class="ponto"></span>${esc(textoSelo)}</span>
            ${contadores ? `<div class="pastilhas">${contadores}</div>` : ''}
          </td>
          <td>${quando}</td>
          <td class="col-mini">${mini(pontos)}</td>
          <td class="num fraco">${esc(duracao(l.duracao_segundos))}</td>
          <td class="num">${esc(bytes(l.origem_conhecida))}</td>
          <td class="num">${esc(bytes(l.destino_conhecido))}</td>
          <td class="col-seta"><span class="seta">&rsaquo;</span></td>
        </tr>`;
}

function estilo(): string {
  return `
  <style>
    /* A tela é uma coluna só, com largura de leitura. Antes o conteúdo
       esticava nos 1280px e as colunas de número ficavam a meio metro do
       nome do cartório, com um vão vazio no meio. */
    .topo-tela { display:flex; align-items:flex-start; justify-content:space-between; gap:18px; }
    .relogio { color:var(--texto3); }
    #btn-atualizar { background:transparent; border:1px solid var(--borda);
                     color:var(--texto2); border-radius:7px; padding:8px 14px;
                     font-size:13px; cursor:pointer; font-family:inherit;
                     white-space:nowrap; margin-top:6px; }
    #btn-atualizar:hover { border-color:var(--azul); color:var(--azul); }

    /* o minigráfico: colunas de 3px, largura fixa, só a altura é dado */
    .col-mini { width:120px; }
    .mini { display:inline-flex; align-items:flex-end; gap:2px; height:26px; }
    .mini i { width:3px; border-radius:2px 2px 0 0; background:var(--azul);
              opacity:.85; display:block; }
    .mini i.avi { background:var(--aviso); opacity:1; }
    .mini i.err { background:var(--erro); opacity:1; }
    .mini-vazio { color:var(--texto3); }

    .col-seta { width:24px; text-align:right; }
    .seta { color:var(--texto3); font-size:20px; line-height:1; }
    #tabela tr.ln:hover .seta { color:var(--azul); }

    /* a faixa do topo: uma frase, não uma parede de números */
    .faixa { display:flex; gap:14px; align-items:flex-start; padding:15px 18px;
             border-radius:10px; margin:20px 0 22px; border:1px solid transparent; }
    .faixa .ic { width:26px; height:26px; border-radius:50%; flex:none; display:flex;
                 align-items:center; justify-content:center; font-weight:700; font-size:14px; }
    .faixa strong { display:block; font-size:15px; margin-bottom:3px; }
    .faixa span:not(.ic) { font-size:13px; color:var(--texto2); line-height:1.6; }
    .faixa a { color:var(--texto); text-decoration:none; font-weight:600; }
    .faixa a:hover { color:var(--azul); }
    .faixa em { font-style:normal; color:var(--texto2); }
    .faixa.tudo-ok { background:rgba(34,197,94,.07); border-color:rgba(34,197,94,.22); }
    .faixa.tudo-ok .ic { background:rgba(34,197,94,.16); color:var(--ok); }
    .faixa.tudo-ok strong { color:var(--ok); }
    .faixa.atencao { background:rgba(245,165,36,.07); border-color:rgba(245,165,36,.24); }
    .faixa.atencao .ic { background:rgba(245,165,36,.16); color:var(--aviso); }
    .faixa.atencao strong { color:var(--aviso); }
    .faixa.grave { background:rgba(243,67,107,.07); border-color:rgba(243,67,107,.26); }
    .faixa.grave .ic { background:rgba(243,67,107,.16); color:var(--erro); }
    .faixa.grave strong { color:var(--erro); }

    .ferramentas { display:flex; gap:12px; align-items:center; margin-bottom:14px; flex-wrap:wrap; }
    #busca { flex:1; min-width:220px; padding:9px 13px; background:var(--fundo);
             color:var(--texto); border:1px solid var(--borda); border-radius:7px;
             font-size:14px; font-family:inherit; }
    #busca:focus { outline:none; border-color:var(--azul); }
    .filtros { display:flex; gap:7px; }
    .fil { padding:8px 14px; background:transparent; color:var(--texto2);
           border:1px solid var(--borda); border-radius:7px; font-size:13px;
           font-family:inherit; cursor:pointer; white-space:nowrap; }
    .fil span { color:var(--texto3, #5A616F); margin-left:5px; }
    .fil:hover { border-color:var(--azul); color:var(--texto); }
    .fil.ativo { background:var(--azul); border-color:var(--azul); color:var(--fundo); font-weight:600; }
    .fil.ativo span { color:var(--fundo); opacity:.75; }

    #tabela th[data-ord] { cursor:pointer; user-select:none; }
    #tabela th[data-ord]:hover { color:var(--texto); }
    #tabela th[data-ord]::after { content:''; }
    #tabela th.asc::after { content:' \\2191'; color:var(--azul); }
    #tabela th.desc::after { content:' \\2193'; color:var(--azul); }

    /* a linha inteira é o alvo do clique, não só o nome. Um alvo de 20px de
       largura no meio de uma linha de 1200px é um teste de pontaria. */
    #tabela tr.ln { cursor:pointer; }
    #tabela tr.ln:hover td { background:#21252F; }

    /* a linha que pede atenção ganha uma marca na lateral, não um fundo
       colorido: fundo colorido em várias linhas vira um arco-íris ilegível */
    #tabela tr.ln.atencao td:first-child { box-shadow:inset 3px 0 0 var(--aviso); }
    #tabela tr.ln.inativo { opacity:.5; }
    #tabela tr.ln.oculta { display:none; }

    .pastilhas { display:flex; gap:5px; margin-top:5px; }
    .pas { border-radius:999px; padding:1px 8px; font-size:11px; font-weight:600; }
    .pas.aviso { background:rgba(245,165,36,.14); color:var(--aviso); }
    .pas.erro  { background:rgba(243,67,107,.14); color:var(--erro); }

    .cidade.alerta-atrasado { color:var(--aviso); }
    .cidade.alerta-parado   { color:var(--erro); font-weight:600; }
    .cidade.alerta-nunca    { color:var(--erro); }

    .sem-resultado { padding:34px; text-align:center; color:var(--texto2); font-size:14px; }

    @media (max-width:760px) {
      .topo-tela { flex-direction:column; }
      .ferramentas { flex-direction:column; align-items:stretch; }
      .filtros { justify-content:stretch; }
      .fil { flex:1; text-align:center; }
    }
  </style>`;
}

function script(): string {
  // Sem framework e sem dependência: são poucas linhas e o painel precisa
  // continuar abrindo daqui a alguns anos sem nada para reconstruir.
  return `
  <script>
  (function () {
    var tabela = document.getElementById('tabela');
    if (!tabela) return;
    var corpo = tabela.tBodies[0];
    var busca = document.getElementById('busca');
    var semResultado = document.getElementById('sem-resultado');
    var filtro = 'todos';

    function aplicar() {
      var termo = (busca.value || '').trim().toLowerCase();
      var visiveis = 0;
      Array.prototype.forEach.call(corpo.rows, function (tr) {
        var casaBusca = !termo || tr.dataset.busca.indexOf(termo) !== -1;
        var casaFiltro = filtro === 'todos' || tr.dataset.atencao === '1';
        var mostra = casaBusca && casaFiltro;
        tr.classList.toggle('oculta', !mostra);
        if (mostra) visiveis++;
      });
      semResultado.hidden = visiveis > 0;
      try { sessionStorage.setItem('painel-busca', busca.value);
            sessionStorage.setItem('painel-filtro', filtro); } catch (e) {}
    }

    busca.addEventListener('input', aplicar);

    // Linha inteira clicável. O link no nome continua existindo para quem
    // navega por teclado e para abrir em outra aba com o botão do meio.
    corpo.addEventListener('click', function (e) {
      if (e.target.closest('a')) return;             // o link cuida de si
      if (window.getSelection().toString()) return;  // estava selecionando texto
      var tr = e.target.closest('tr.ln');
      if (tr && tr.dataset.ir) location.href = tr.dataset.ir;
    });

    Array.prototype.forEach.call(document.querySelectorAll('.fil'), function (b) {
      b.addEventListener('click', function () {
        document.querySelectorAll('.fil').forEach(function (o) { o.classList.remove('ativo'); });
        b.classList.add('ativo');
        filtro = b.dataset.fil;
        aplicar();
      });
    });

    // Ordenação por coluna. O primeiro clique põe o mais relevante em cima:
    // para número e data isso é o maior; para nome, o alfabético.
    var ordemAtual = null, invertido = false;
    Array.prototype.forEach.call(tabela.querySelectorAll('th[data-ord]'), function (th) {
      th.addEventListener('click', function () {
        var chave = th.dataset.ord;
        invertido = (ordemAtual === chave) ? !invertido : false;
        ordemAtual = chave;

        tabela.querySelectorAll('th').forEach(function (o) { o.classList.remove('asc', 'desc'); });

        var texto = (chave === 'nome');
        var linhas = Array.prototype.slice.call(corpo.rows);
        linhas.sort(function (a, b) {
          var va = a.dataset[chave], vb = b.dataset[chave];
          var r = texto ? String(va).localeCompare(String(vb), 'pt-BR')
                        : (Number(vb) - Number(va));
          // "situacao" é peso: menor é pior, então o pior vem primeiro
          if (chave === 'situacao') r = Number(a.dataset.situacao) - Number(b.dataset.situacao);
          return invertido ? -r : r;
        });
        linhas.forEach(function (tr) { corpo.appendChild(tr); });
        th.classList.add(invertido ? 'desc' : 'asc');
      });
    });

    // Devolve busca e filtro depois de recarregar, senão a atualização
    // automática apagaria o que a pessoa acabou de digitar.
    try {
      var b = sessionStorage.getItem('painel-busca');
      var f = sessionStorage.getItem('painel-filtro');
      if (b) busca.value = b;
      if (f && f !== 'todos') {
        var alvo = document.querySelector('.fil[data-fil="' + f + '"]');
        if (alvo) alvo.click(); else aplicar();
      } else { aplicar(); }
    } catch (e) { aplicar(); }

    // Relógio e atualização automática. Um painel de monitoramento que
    // envelhece calado é pior que nenhum: quem olha acha que está vendo agora.
    var nascimento = Date.now();
    var relogio = document.getElementById('relogio');
    setInterval(function () {
      var s = Math.round((Date.now() - nascimento) / 1000);
      relogio.textContent = s < 60 ? 'atualizado agora'
                          : 'atualizado há ' + Math.floor(s / 60) + ' min';
    }, 15000);

    document.getElementById('btn-atualizar').addEventListener('click', function () {
      location.reload();
    });

    // Não recarrega enquanto a pessoa está digitando na busca.
    setInterval(function () {
      if (document.activeElement === busca) return;
      location.reload();
    }, 120000);
  })();
  </script>`;
}

function vazio(): string {
  return `
  <h1>Cartórios</h1>
  <p class="legenda">Nenhum cartório cadastrado ainda.</p>

  <div class="vazio">
    <strong>Comece cadastrando o primeiro cartório</strong>
    <p>Vá em <a href="/cartorios">Cartórios</a> e preencha o formulário, ou
       pelo terminal:</p>
    <p><code>npm run criar-cliente -- "Nome do Cartório" "Cidade"</code></p>
    <p style="margin-top:18px">
      Você recebe uma URL pronta para colar no<br>
      <code>send-http-json-urls</code> do Duplicati daquele cartório.
    </p>
  </div>`;
}
