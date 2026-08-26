import { esc, bytes as formatarBytes, dataHora, tempoDesde } from '../util/formato';

/**
 * A tela do CH.Com Cofre — a cópia externa para desastre.
 *
 * O QUE ESTA TELA RESPONDE, E QUE AS OUTRAS NÃO RESPONDEM
 *
 * O painel de backup mostra "o último backup deu certo?". Esta tela mostra
 * outra coisa: "há quanto tempo CADA COISA não sobe?".
 *
 * A diferença importa porque uma execução recente bem-sucedida pode não ter
 * tocado numa VM parada há três meses — a VM não entrou naquela rodada, nada
 * falhou, e o painel mostraria verde. O buraco fica invisível justamente
 * porque nada deu errado.
 *
 * Por isso o centro da tela é a lista de ITENS com a data do último sucesso
 * de cada um, e não a lista de execuções. As execuções vêm depois, como
 * histórico.
 */

export interface ItemProtegido {
  tipo: string;
  nome: string;
  maquina: string;
  consistencia: string | null;
  bytes: number;
  quando: string | null;
}

export interface ExecucaoResumo {
  id: number;
  maquina: string;
  recebido_em: string;
  terminou_em: string | null;
  resultado: string | null;
  itens: number;
  sucessos: number;
  falhas: number;
}

/**
 * Quantos dias de folga cada tipo tem antes de virar problema.
 *
 * Não é o mesmo número para tudo, e tratar como se fosse produziria alarme
 * falso ou silêncio perigoso:
 *
 *   VM e imagem   sobem uma vez por mês. 45 dias é folga normal; 75 é sinal
 *                 de que a rodada mensal parou de acontecer.
 *   banco e pasta sobem todo dia. 3 dias já é estranho; 7 é problema.
 */
function limiteDeDias(tipo: string): { aviso: number; erro: number } {
  if (tipo === 'vm' || tipo === 'imagem') return { aviso: 45, erro: 75 };
  return { aviso: 3, erro: 7 };
}

function rotuloDoTipo(tipo: string): string {
  switch (tipo) {
    case 'vm':
      return 'Máquina virtual';
    case 'imagem':
      return 'Imagem do servidor';
    case 'firebird':
      return 'Banco Firebird';
    case 'sqlserver':
      return 'Banco SQL Server';
    case 'pasta':
      return 'Pasta ou disco';
    default:
      return tipo;
  }
}

function diasDesde(iso: string | null): number | null {
  if (!iso) return null;
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return null;
  return Math.floor((Date.now() - t) / 86_400_000);
}

/** A bolinha de estado, com o mesmo significado do resto do painel. */
function selo(estado: 'ok' | 'aviso' | 'erro' | 'sem-dados', texto: string): string {
  return `<span class="selo ${estado}">${esc(texto)}</span>`;
}

/**
 * A linha de um item protegido.
 *
 * A consistência aparece SEMPRE, mesmo quando está tudo certo. Não é
 * enfeite: um item verde crash-consistent não é a mesma coisa que um item
 * verde application-consistent. O primeiro foi copiado como se tivesse
 * faltado energia — costuma restaurar, mas não há promessa. Esconder essa
 * diferença é transformar duas coisas diferentes na mesma luz verde.
 */
function linhaItem(item: ItemProtegido): string {
  const limite = limiteDeDias(item.tipo);

  // "nunca enviado" e "atrasado demais" são coisas diferentes e ficam
  // separadas: o primeiro pode ser agente não instalado ou item novo; o
  // segundo é uma rotina que parou de funcionar.
  const dias = diasDesde(item.quando);
  let estado: 'ok' | 'aviso' | 'erro' | 'sem-dados';
  let quando: string;

  if (dias === null) {
    estado = 'sem-dados';
    quando = 'nunca';
  } else {
    quando = tempoDesde(item.quando);
    estado = dias > limite.erro ? 'erro' : dias > limite.aviso ? 'aviso' : 'ok';
  }

  const crash = (item.consistencia ?? '').toUpperCase().includes('CRASH');

  return `<tr>
    <td>${selo(estado, quando)}</td>
    <td class="tipo">${esc(rotuloDoTipo(item.tipo))}</td>
    <td class="nome">${esc(item.nome)}</td>
    <td class="maquina">${esc(item.maquina)}</td>
    <td class="consistencia${crash ? ' atencao' : ''}">${esc(item.consistencia ?? '—')}</td>
    <td class="numero">${formatarBytes(item.bytes)}</td>
    <td class="numero">${esc(dataHora(item.quando))}</td>
  </tr>`;
}

/**
 * A tela.
 *
 * Recebe tudo pronto: esta função só desenha. Consulta ao banco fica na rota,
 * que é onde dá para testar sem subir HTML.
 */
export function telaCofre(dados: {
  clienteNome: string;
  clienteId: number;
  itens: ItemProtegido[];
  execucoes: ExecucaoResumo[];
}): string {
  const { clienteNome, clienteId, itens, execucoes } = dados;

  // ---- o veredito, numa frase --------------------------------------------
  const comProblema = itens.filter((i) => {
    const d = diasDesde(i.quando);
    return d === null || d > limiteDeDias(i.tipo).erro;
  });
  const emAtraso = itens.filter((i) => {
    const d = diasDesde(i.quando);
    if (d === null) return false;
    const l = limiteDeDias(i.tipo);
    return d > l.aviso && d <= l.erro;
  });
  const crashConsistent = itens.filter((i) =>
    (i.consistencia ?? '').toUpperCase().includes('CRASH'),
  );

  let veredito: string;
  if (itens.length === 0) {
    veredito = `<div class="veredito erro">
      <strong>Este cartório nunca enviou nada para o Cofre</strong>
      <span>O agente pode não estar instalado, ou o token pode estar errado.</span>
    </div>`;
  } else if (comProblema.length > 0) {
    veredito = `<div class="veredito erro">
      <strong>${comProblema.length} item(ns) sem cópia externa há tempo demais</strong>
      <span>${esc(comProblema.map((i) => i.nome).join(', '))}</span>
    </div>`;
  } else if (emAtraso.length > 0) {
    veredito = `<div class="veredito aviso">
      <strong>${emAtraso.length} item(ns) começando a atrasar</strong>
      <span>Ainda dentro do aceitável, mas vale olhar.</span>
    </div>`;
  } else {
    veredito = `<div class="veredito ok">
      <strong>Cópia externa em dia</strong>
      <span>${itens.length} item(ns) protegidos, todos dentro do prazo.</span>
    </div>`;
  }

  // Este aviso é separado do veredito de propósito: itens crash-consistent
  // estão VERDES — subiram, foram conferidos, estão na AWS. O problema não é
  // o envio, é a promessa. Misturar com "atrasado" esconderia os dois.
  const avisoCrash =
    crashConsistent.length > 0
      ? `<div class="veredito aviso">
          <strong>${crashConsistent.length} item(ns) sem garantia de consistência</strong>
          <span>${esc(crashConsistent.map((i) => i.nome).join(', '))} — copiados como se tivesse faltado energia.
          Costuma restaurar, mas não há promessa. Instale os Serviços de Integração dentro da VM.</span>
        </div>`
      : '';

  // ---- a tabela de itens: o centro da tela -------------------------------
  const tabelaItens =
    itens.length === 0
      ? `<p class="vazio">Nada foi enviado para o Cofre ainda.</p>`
      : `<div class="tabela-area">
          <table>
            <thead><tr>
              <th>Último envio</th><th>Tipo</th><th>O quê</th><th>Servidor</th>
              <th>Consistência</th><th class="numero">Tamanho</th><th class="numero">Quando</th>
            </tr></thead>
            <tbody>${itens.map(linhaItem).join('')}</tbody>
          </table>
         </div>`;

  // ---- histórico de execuções --------------------------------------------
  const linhasExec = execucoes
    .map((e) => {
      const estado =
        e.falhas > 0 ? (e.sucessos > 0 ? 'aviso' : 'erro') : 'ok';
      const texto =
        e.falhas > 0 ? `${e.falhas} falha(s)` : 'sem falha';
      return `<tr>
        <td>${selo(estado, texto)}</td>
        <td class="maquina">${esc(e.maquina)}</td>
        <td>${esc(e.resultado ?? '—')}</td>
        <td class="numero">${e.sucessos} de ${e.itens}</td>
        <td class="numero">${esc(dataHora(e.terminou_em ?? e.recebido_em))}</td>
      </tr>`;
    })
    .join('');

  const tabelaExec =
    execucoes.length === 0
      ? ''
      : `<h2>Execuções</h2>
         <div class="tabela-area">
           <table>
             <thead><tr>
               <th>Resultado</th><th>Servidor</th><th>Situação</th>
               <th class="numero">Itens</th><th class="numero">Quando</th>
             </tr></thead>
             <tbody>${linhasExec}</tbody>
           </table>
         </div>`;

  return `
<a class="voltar" href="/cartorio/${clienteId}">&larr; voltar para o cartório</a>

<h1>Cofre — ${esc(clienteNome)}</h1>
<p class="subtitulo">Cópia externa para desastre. Não substitui o backup local do cartório.</p>

${veredito}
${avisoCrash}

<h2>O que está protegido</h2>
<p class="ajuda">A data é a do <strong>último envio bem-sucedido de cada item</strong> —
e não a da última execução. Uma rodada recente pode não ter tocado numa VM
parada há meses, e é esse buraco que passa despercebido.</p>
${tabelaItens}

${tabelaExec}
`;
}
