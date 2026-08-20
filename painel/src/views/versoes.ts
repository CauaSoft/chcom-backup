import type { LinhaHistorico, MensagensDoRelatorio } from '../db/repo';
import {
  bytes,
  dataHora,
  duracao,
  esc,
  numero,
  situacaoDe,
  velocidade,
  type Situacao,
} from '../util/formato';

/**
 * Histórico de versões.
 *
 * ERA UM CARTÃO POR EXECUÇÃO, E ESTAVA ERRADO
 *
 * Cada cartão repetia os cinco rótulos — "Com backup", "Velocidade", "Tempo
 * gasto", "Dados a recuperar", "Método". Com 45 execuções eram 225 rótulos na
 * tela dizendo a mesma coisa, e responder "qual noite foi a mais lenta?"
 * obrigava a ler 45 blocos separados.
 *
 * Numa tabela o rótulo aparece uma vez no topo e os números ficam alinhados
 * na mesma coluna: o olho corre e a comparação sai de graça.
 *
 * O QUE FALTAVA
 *
 * Quando uma execução falhava, a tela dizia "2 erros" e não dizia quais. O
 * trabalho de descobrir sobrava para quem estava lendo — que é exatamente o
 * que esta tela existe para evitar. Agora o texto do erro aparece logo abaixo
 * da linha, à vista, sem clique.
 */

const ROTULO_ACAO: Record<Situacao, string> = {
  ok: 'com êxito',
  aviso: 'com avisos',
  erro: 'falhou',
  'sem-dados': 'sem informação',
};

const ICONE: Record<Situacao, string> = {
  ok: '&#10003;',
  aviso: '!',
  erro: '&#10007;',
  'sem-dados': '?',
};

export function blocoVersoes(
  historico: LinhaHistorico[],
  mensagens?: Map<number, MensagensDoRelatorio>,
): string {
  if (historico.length === 0) return '';

  // A mais antiga registrada é a que criou o backup do zero. O Duplicati faz
  // uma só; daí em diante tudo é incremental.
  const idMaisAntigo = historico[historico.length - 1]?.id;

  return `
  <div class="versoes-topo">
    <span class="contador-versoes">${numero(historico.length)} ${
      historico.length === 1 ? 'versão' : 'versões'
    }</span>
    <span class="versoes-dica">uma por execução, da mais recente para a mais antiga</span>
  </div>

  <div class="tabela-area">
    <table class="tb-versoes">
      <thead>
        <tr>
          <th>Quando</th>
          <th>Situação</th>
          <th class="num">Enviado</th>
          <th class="num">Velocidade</th>
          <th class="num">Duração</th>
          <th class="num">Na nuvem</th>
        </tr>
      </thead>
      <tbody>
        ${historico.map((h) => linha(h, h.id === idMaisAntigo, mensagens?.get(h.id))).join('\n')}
      </tbody>
    </table>
  </div>

  ${CSS}`;
}

function linha(
  h: LinhaHistorico,
  ehCompleto: boolean,
  msgs?: MensagensDoRelatorio,
): string {
  const sit = situacaoDe(h.resultado);
  const quando = h.fim_em ?? h.recebido_em;

  const todas = [...(msgs?.erros ?? []), ...(msgs?.avisos ?? [])];
  const temDetalhe = todas.length > 0;

  const principal = `
        <tr class="lv ${sit}${temDetalhe ? ' com-det' : ''}">
          <td class="q">
            ${esc(dataHora(quando))}
            ${ehCompleto ? '<span class="tag">completo</span>' : ''}
          </td>
          <td>
            <span class="est ${sit}">
              <span class="ic ${sit}" aria-hidden="true">${ICONE[sit]}</span>${esc(ROTULO_ACAO[sit])}
            </span>
          </td>
          <td class="num" data-r="Enviado">${esc(bytes(h.bytes_enviados))}</td>
          <td class="num" data-r="Velocidade">${esc(
            velocidade(h.bytes_enviados, h.duracao_segundos),
          )}</td>
          <td class="num" data-r="Duração">${esc(duracao(h.duracao_segundos))}</td>
          <td class="num${(h.tamanho_destino ?? 0) > 0 ? '' : ' fraco'}" data-r="Na nuvem">${esc(
            (h.tamanho_destino ?? 0) > 0 ? bytes(h.tamanho_destino) : '—',
          )}</td>
        </tr>`;

  if (!temDetalhe) return principal;

  return (
    principal +
    `
        <tr class="det ${sit}">
          <td colspan="6">
            <div class="cxerro">
              <div class="cru">${todas.map((t) => `<div>${esc(t)}</div>`).join('')}</div>
            </div>
          </td>
        </tr>`
  );
}

const CSS = `
<style>
.versoes-topo {
  display: flex; align-items: center; gap: 14px;
  flex-wrap: wrap; margin-bottom: 14px;
}

/* O contador é o número que o produto existe para mostrar. */
.contador-versoes {
  background: rgba(34,197,94,.13);
  color: var(--ok);
  border: 1px solid rgba(34,197,94,.3);
  border-radius: 999px;
  padding: 6px 16px;
  font-size: 14px; font-weight: 600; white-space: nowrap;
}
.versoes-dica { color: var(--texto3); font-size: 13px; }

.tb-versoes { width: 100%; border-collapse: collapse; font-size: 13.5px; }
.tb-versoes th {
  color: var(--texto3); font-size: 11.5px; font-weight: 500;
  text-align: left; padding: 0 14px 8px 0;
  border-bottom: 1px solid var(--borda); white-space: nowrap;
}
/* Números à direita e com dígitos de largura igual: é o que deixa a coluna
   comparável de cima a baixo. */
.tb-versoes th.num, .tb-versoes td.num {
  text-align: right; font-variant-numeric: tabular-nums;
}
.tb-versoes td {
  padding: 11px 14px 11px 0;
  border-top: 1px solid #23272F; white-space: nowrap;
}
.tb-versoes tbody tr:first-child td { border-top: none; }
.tb-versoes td.num { font-weight: 600; color: var(--texto); }
.tb-versoes td.num.fraco { color: var(--texto3); font-weight: 500; }
.tb-versoes td.q { color: var(--texto2); padding-right: 20px; }

.tb-versoes .tag {
  background: #232734; color: var(--texto3); border-radius: 4px;
  padding: 1px 6px; font-size: 10.5px; margin-left: 6px; vertical-align: 1px;
}

/* Estado = ícone + palavra + cor. Cor sozinha nunca: verde e vermelho é
   justamente o par que quem tem daltonismo não distingue. */
.tb-versoes .est {
  display: inline-flex; align-items: center; gap: 8px;
  color: var(--texto2); white-space: nowrap;
}
.tb-versoes .est.erro  { color: var(--erro); font-weight: 600; }
.tb-versoes .est.aviso { color: var(--aviso); }
.tb-versoes .ic {
  width: 18px; height: 18px; border-radius: 50%; flex: none;
  display: flex; align-items: center; justify-content: center;
  font-size: 11px; font-weight: 700;
}
.tb-versoes .ic.ok    { background: rgba(34,197,94,.16);  color: var(--ok); }
.tb-versoes .ic.aviso { background: rgba(245,165,36,.16); color: var(--aviso); }
.tb-versoes .ic.erro  { background: rgba(243,67,107,.16); color: var(--erro); }
.tb-versoes .ic.sem-dados { background: #232734; color: var(--texto3); }

/* A linha de detalhe pertence à de cima: sem risco entre as duas. */
.tb-versoes tr.lv.com-det td { border-bottom: none; }
.tb-versoes tr.det td {
  border-top: none; padding: 0 0 12px 0; white-space: normal;
}
.cxerro {
  background: #191C24; border: 1px solid var(--borda);
  border-left: 3px solid var(--erro); border-radius: 0 8px 8px 0;
  padding: 11px 14px;
}
.tb-versoes tr.det.aviso .cxerro { border-left-color: var(--aviso); }
.cru {
  color: var(--texto3); font-size: 12px; line-height: 1.55;
  font-family: Consolas, "Courier New", monospace; word-break: break-word;
}
.cru div + div { margin-top: 5px; }

/* Telas estreitas: a tabela vira blocos, com o rótulo ao lado do valor. */
@media (max-width: 700px) {
  .tb-versoes thead { display: none; }
  .tb-versoes, .tb-versoes tbody, .tb-versoes tr, .tb-versoes td { display: block; width: auto; }
  .tb-versoes tr.lv { border-top: 1px solid #23272F; padding: 10px 0; }
  .tb-versoes td { border: none; padding: 2px 0; text-align: left !important; }
  .tb-versoes td.num::before {
    content: attr(data-r); color: var(--texto3);
    font-size: 11.5px; margin-right: 8px; font-weight: 500;
  }
}
</style>`;
