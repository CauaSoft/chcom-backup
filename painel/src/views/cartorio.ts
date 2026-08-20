import type { Cliente, LinhaHistorico, MensagensDoRelatorio } from '../db/repo';
import {
  atrasoDe,
  bytes,
  esc,
  HORAS_ATRASADO,
  numero,
  ROTULO_ATRASO,
  ROTULO_SITUACAO,
  situacaoDe,
  tempoDesde,
} from '../util/formato';
import { graficoCrescimento } from './grafico';
import { blocoVersoes } from './versoes';
import { pagina } from './layout';

export function telaCartorio(
  cliente: Cliente,
  historico: LinhaHistorico[],
  urlRelatorio: string,
  mensagens?: Map<number, MensagensDoRelatorio>,
  usuario?: string,
): string {
  const ultimo = historico[0] ?? null;
  const sit = situacaoDe(ultimo?.resultado);

  /**
   * Um backup que PAROU de acontecer não pode aparecer como "Sucesso" aqui,
   * pelo mesmo motivo que não pode na lista: o último relatório continua
   * dizendo que deu certo para sempre, porque não chega relatório novo para
   * contradizê-lo. Se o painel marca este cartório como parado, esta tela
   * precisa dizer a mesma coisa — senão uma contradiz a outra.
   */
  const atraso = atrasoDe(ultimo ? (ultimo.fim_em ?? ultimo.recebido_em) : null);
  const mandaOAtraso = sit === 'ok' && (atraso === 'atrasado' || atraso === 'parado');
  const classeSelo = mandaOAtraso ? (atraso === 'parado' ? 'erro' : 'aviso') : sit;
  const textoSelo = mandaOAtraso ? ROTULO_ATRASO[atraso] : ROTULO_SITUACAO[sit];

  // Só entram no gráfico os relatórios com tamanho de destino REAL.
  //
  // O `> 0` não é paranoia: quando o backup falha antes de conseguir listar
  // o destino, o Duplicati reporta KnownFileSize igual a 0 — e isso foi visto
  // num backup real, não suposto. Ali zero significa "não consegui medir",
  // não "não há nada lá". Deixar entrar desenha uma queda a zero no meio do
  // gráfico, como se o backup tivesse sido apagado da nuvem.
  const pontos = historico
    .filter((h) => typeof h.tamanho_destino === 'number' && h.tamanho_destino > 0)
    .map((h) => ({
      quando: h.fim_em ?? h.recebido_em,
      valor: h.tamanho_destino as number,
    }));

  /**
   * Último valor CONHECIDO, não o do último relatório.
   *
   * Se o backup mais recente falhou, ele traz 0 nas métricas. Mostrar 0 B em
   * "total no destino" faria parecer que o backup sumiu da nuvem, quando na
   * verdade ele continua lá — o que falhou foi a execução de hoje. Então
   * procuramos para trás o relatório mais recente que conseguiu medir.
   */
  const ultimoConhecido = (
    campo: 'tamanho_destino' | 'tamanho_origem',
  ): number | null => {
    for (const h of historico) {
      const v = h[campo];
      if (typeof v === 'number' && v > 0) return v;
    }
    return null;
  };

  const destinoAtual = ultimoConhecido('tamanho_destino');
  const origemAtual = ultimoConhecido('tamanho_origem');

  // Avisa quando o número exibido não é do backup mais recente, para ninguém
  // ler um dado velho achando que é de hoje.
  const destinoDesatualizado =
    destinoAtual !== null &&
    ultimo !== null &&
    (ultimo.tamanho_destino ?? 0) <= 0;

  /**
   * Quantos backups DIFERENTES este cartório reporta.
   *
   * Um cartório pode ter mais de um backup configurado no Duplicati — a base
   * do sistema e os documentos digitalizados, por exemplo — e todos usam o
   * mesmo token. Quando isso acontece, o histórico abaixo mistura execuções
   * de coisas distintas, e comparar tamanhos entre elas não quer dizer nada.
   * Melhor avisar do que deixar alguém tirar a conclusão errada.
   */
  const nomesDeBackup = [
    ...new Set(
      historico
        .map((h) => h.backup_nome)
        .filter((n): n is string => typeof n === 'string' && n !== ''),
    ),
  ];

  const corpo = `
  <a href="/" class="voltar">← Todos os cartórios</a>

  <h1>${esc(cliente.nome)}</h1>
  <p class="legenda">
    ${esc(cliente.cidade)}
    ${cliente.ativo ? '' : ' · <span style="color:var(--aviso)">desativado</span>'}
  </p>

  <div class="cartoes">
    <div class="cartao">
      <div class="rotulo">Situação</div>
      <div class="valor" style="font-size:19px;padding-top:4px">
        <span class="selo ${classeSelo}"><span class="ponto"></span>${esc(textoSelo)}</span>
      </div>
      <div class="nota ${mandaOAtraso ? 'alerta' : ''}">${
        ultimo ? esc(tempoDesde(ultimo.fim_em ?? ultimo.recebido_em)) : 'sem relatórios'
      }</div>
    </div>
    <div class="cartao">
      <div class="rotulo">Total na nuvem</div>
      <div class="valor">${esc(bytes(destinoAtual))}</div>
      <div class="nota">${destinoDesatualizado ? '<span style="color:var(--aviso)">do último backup que mediu</span>' : 'guardado na AWS S3'}</div>
    </div>
    <div class="cartao">
      <div class="rotulo">Tamanho da origem</div>
      <div class="valor">${esc(bytes(origemAtual))}</div>
      <div class="nota">examinado no servidor</div>
    </div>
    <div class="cartao">
      <div class="rotulo">Versões recebidas</div>
      <div class="valor">${numero(historico.length)}</div>
      <div class="nota">execuções reportadas</div>
    </div>
  </div>

  ${historico.length === 0 ? semRelatorios(urlRelatorio) : ''}

  ${historico.length > 0 ? graficoCrescimento(pontos, 'Crescimento do backup no destino') : ''}

  ${
    historico.length > 0
      ? `
  <h2>Histórico de versões</h2>

  ${
    nomesDeBackup.length > 1
      ? `<p class="legenda" style="color:var(--aviso)">
           Atenção: este cartório reporta ${nomesDeBackup.length} backups
           diferentes (${nomesDeBackup.map(esc).join(', ')}) no mesmo token.
           As linhas abaixo estão misturadas — compare os tamanhos apenas
           dentro do mesmo backup.
         </p>`
      : ''
  }

  ${blocoVersoes(historico, mensagens)}`
      : ''
  }

  <h2>Configuração no Duplicati</h2>
  <p class="legenda">
    Esta é a URL deste cartório. No Duplicati do servidor dele, vá em
    <strong>Configurações → Opções avançadas</strong> e defina
    <code>send-http-json-urls</code> com este valor:
  </p>
  <div class="tabela-area" style="padding:16px">
    <code style="display:block;padding:10px 12px">${esc(urlRelatorio)}</code>
  </div>
  <p class="rodape">
    O token nessa URL é o que identifica este cartório. Não reaproveite o
    token de um cartório em outro: os relatórios ficariam misturados na mesma
    linha do painel.
    Um cartório é marcado como <strong>atrasado</strong> após ${HORAS_ATRASADO} h
    sem reportar, mesmo que o último relatório dele tenha dado certo.
  </p>

  <style>
    .cartao .nota.alerta { color: var(--aviso); font-weight: 600; }
  </style>`;

  return pagina({ titulo: cliente.nome, corpo, usuario });
}

function semRelatorios(url: string): string {
  return `
  <div class="vazio">
    <strong>Este cartório ainda não reportou nenhum backup</strong>
    <p>Configure o <code>send-http-json-urls</code> no Duplicati dele com a URL abaixo<br>
       e rode um backup. O relatório aparece aqui automaticamente.</p>
    <p style="margin-top:18px"><code>${esc(url)}</code></p>
    <p style="margin-top:18px;font-size:13px">
      Se já configurou e nada apareceu, confira a
      <a href="/calibracao">calibração</a> — recebimentos recusados por
      token errado ficam registrados lá.
    </p>
  </div>`;
}
