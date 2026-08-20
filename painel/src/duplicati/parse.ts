/**
 * Leitura do JSON que o Duplicati envia em `send-http-json-urls`.
 *
 * ---------------------------------------------------------------------------
 * A POSTURA DESTE ARQUIVO: desconfiar do formato
 *
 * Os nomes dos campos abaixo vieram de um relatório real, mas de UMA versão
 * do Duplicati, de UM backup. Versões diferentes movem campos de lugar, e um
 * backup que falha cedo manda um relatório bem mais magro que um que deu
 * certo.
 *
 * Então nada aqui presume estrutura. Cada campo é buscado em mais de um
 * caminho possível, qualquer ausência vira `null` em vez de erro, e o parser
 * devolve junto um diagnóstico dizendo o que encontrou e o que não. Esse
 * diagnóstico é o que alimenta o modo calibração — a ideia é você disparar um
 * backup de teste e conferir na tela se a leitura bateu, em vez de descobrir
 * um mês depois que a coluna estava vazia o tempo todo.
 *
 * Se um campo estiver diferente, o lugar de corrigir é aqui, e o JSON bruto
 * guardado no banco permite reprocessar o histórico depois da correção.
 * ---------------------------------------------------------------------------
 */

/**
 * Versão 2: passou a ler backup_nome e maquina_nome, depois da calibração
 * contra um Duplicati 2.3.0.4 real. Relatórios gravados com a versão 1 têm
 * esses campos vazios, mas o JSON bruto deles continua no banco — dá para
 * reprocessar quando fizer falta.
 */
export const VERSAO_PARSER = 2;

export interface CamposExtraidos {
  resultado: string | null;
  operacao: string | null;
  /** Nome do backup no Duplicati. Um cartório pode ter mais de um. */
  backupNome: string | null;
  /** Nome do servidor onde o Duplicati roda. */
  maquinaNome: string | null;
  inicioEm: string | null;
  fimEm: string | null;
  duracaoSegundos: number | null;
  tamanhoOrigem: number | null;
  tamanhoAdicionado: number | null;
  bytesEnviados: number | null;
  tamanhoDestino: number | null;
  qtdAvisos: number | null;
  qtdErros: number | null;
}

export interface DiagnosticoCampo {
  campo: keyof CamposExtraidos;
  /** Onde o valor foi achado no JSON, ou null se não foi achado em lugar nenhum. */
  caminhoEncontrado: string | null;
  valorBruto: unknown;
  valorConvertido: unknown;
}

export interface ResultadoParse {
  campos: CamposExtraidos;
  diagnostico: DiagnosticoCampo[];
  /** Campos que não foram encontrados. Se esta lista estiver grande, o formato mudou. */
  naoEncontrados: string[];
}

/** Navega um caminho tipo "Data.BackendStatistics.BytesUploaded" com segurança. */
function buscar(objeto: unknown, caminho: string): unknown {
  let atual: unknown = objeto;
  for (const parte of caminho.split('.')) {
    if (atual === null || typeof atual !== 'object') return undefined;
    atual = (atual as Record<string, unknown>)[parte];
  }
  return atual;
}

/** Primeiro caminho que devolver algo diferente de undefined/null. */
function primeiro(
  objeto: unknown,
  caminhos: string[],
): { caminho: string; valor: unknown } | null {
  for (const caminho of caminhos) {
    const valor = buscar(objeto, caminho);
    if (valor !== undefined && valor !== null) return { caminho, valor };
  }
  return null;
}

/**
 * Converte para um inteiro que o SQLite aceita.
 *
 * Devolve null em vez de 0 quando não dá para converter: em bytes, zero é uma
 * afirmação ("nada foi enviado") e null é uma admissão ("não sei"). Trocar um
 * pelo outro faria o painel mostrar 0 B para um cartório cujo relatório veio
 * incompleto, o que parece um backup vazio.
 */
function paraInteiro(valor: unknown): number | null {
  if (typeof valor === 'number') {
    if (!Number.isFinite(valor)) return null;
    const arredondado = Math.round(valor);
    return Number.isSafeInteger(arredondado) ? arredondado : null;
  }
  if (typeof valor === 'string' && valor.trim() !== '') {
    const n = Number(valor);
    if (Number.isFinite(n)) {
      const arredondado = Math.round(n);
      return Number.isSafeInteger(arredondado) ? arredondado : null;
    }
  }
  return null;
}

function paraTexto(valor: unknown): string | null {
  if (typeof valor === 'string' && valor.trim() !== '') return valor.trim();
  if (typeof valor === 'number' || typeof valor === 'boolean') return String(valor);
  return null;
}

/**
 * Normaliza uma data para ISO 8601 UTC.
 *
 * O Duplicati costuma mandar ISO ("2026-08-12T19:30:00Z"), mas dependendo da
 * versão e da cultura do Windows pode vir no formato local. Se não der para
 * interpretar com segurança, devolve null e o valor original continua no
 * json_bruto — melhor uma data vazia do que uma data errada, porque data
 * errada faz o painel dizer que o backup rodou quando não rodou.
 */
function paraDataISO(valor: unknown): string | null {
  if (typeof valor !== 'string' || valor.trim() === '') return null;

  const texto = valor.trim();

  // O Duplicati usa "0001-01-01T00:00:00Z" (DateTime.MinValue do .NET) para
  // dizer "sem valor". Interpretar isso como data real colocaria backups no
  // ano 1 na ordenação do painel.
  if (texto.startsWith('0001-01-01')) return null;

  const ms = Date.parse(texto);
  if (!Number.isFinite(ms)) return null;

  const data = new Date(ms);
  const ano = data.getUTCFullYear();
  if (ano < 2000 || ano > 2100) return null;

  return data.toISOString();
}

/**
 * Converte a duração do .NET ("00:04:12.3456789" ou "1.02:03:04") em segundos.
 *
 * O formato TimeSpan do .NET é [d.]hh:mm:ss[.fffffff] — os dias vêm separados
 * por PONTO, não por dois-pontos, e é fácil confundir com os segundos
 * fracionários. Um backup de mais de 24 horas cairia nesse caso.
 */
export function duracaoParaSegundos(valor: unknown): number | null {
  if (typeof valor === 'number' && Number.isFinite(valor)) {
    return Math.round(valor);
  }
  if (typeof valor !== 'string' || valor.trim() === '') return null;

  const texto = valor.trim();
  const m = /^(?:(\d+)\.)?(\d{1,2}):(\d{2}):(\d{2})(?:\.(\d+))?$/.exec(texto);
  if (!m) return null;

  const dias = m[1] ? Number(m[1]) : 0;
  const horas = Number(m[2]);
  const minutos = Number(m[3]);
  const segundos = Number(m[4]);
  const fracao = m[5] ? Number('0.' + m[5]) : 0;

  if ([dias, horas, minutos, segundos].some((n) => !Number.isFinite(n))) return null;

  return Math.round(dias * 86400 + horas * 3600 + minutos * 60 + segundos + fracao);
}

/**
 * Onde procurar cada campo, em ordem de preferência.
 *
 * O primeiro caminho é o documentado. Os seguintes cobrem variações já vistas
 * em versões diferentes do Duplicati — sobretudo relatórios que vêm sem o
 * envelope "Data" em volta.
 */
const CAMINHOS = {
  resultado: ['Data.ParsedResult', 'ParsedResult', 'Data.MainOperationResult'],
  operacao: ['Data.MainOperation', 'MainOperation', 'Extra.OperationName'],

  // Confirmados num relatório real do Duplicati 2.3.0.4. Ficam em Extra, com
  // nomes separados por hífen — não em Data como o resto.
  backupNome: ['Extra.backup-name', 'Data.Extra.backup-name'],
  maquinaNome: ['Extra.machine-name', 'Data.Extra.machine-name'],

  inicioEm: ['Data.BeginTime', 'BeginTime'],
  fimEm: ['Data.EndTime', 'EndTime'],
  duracaoSegundos: ['Data.Duration', 'Duration'],
  tamanhoOrigem: ['Data.SizeOfExaminedFiles', 'SizeOfExaminedFiles'],
  tamanhoAdicionado: ['Data.SizeOfAddedFiles', 'SizeOfAddedFiles'],
  bytesEnviados: [
    'Data.BackendStatistics.BytesUploaded',
    'BackendStatistics.BytesUploaded',
    'Data.BytesUploaded',
  ],
  tamanhoDestino: [
    'Data.BackendStatistics.KnownFileSize',
    'BackendStatistics.KnownFileSize',
    'Data.KnownFileSize',
  ],
  qtdAvisos: [
    'Data.WarningsActualLength',
    'WarningsActualLength',
    'Data.BackendStatistics.WarningsActualLength',
  ],
  qtdErros: [
    'Data.ErrorsActualLength',
    'ErrorsActualLength',
    'Data.BackendStatistics.ErrorsActualLength',
  ],
} as const satisfies Record<keyof CamposExtraidos, readonly string[]>;

type Conversor = (v: unknown) => string | number | null;

const CONVERSORES: Record<keyof CamposExtraidos, Conversor> = {
  resultado: paraTexto,
  operacao: paraTexto,
  backupNome: paraTexto,
  maquinaNome: paraTexto,
  inicioEm: paraDataISO,
  fimEm: paraDataISO,
  duracaoSegundos: duracaoParaSegundos,
  tamanhoOrigem: paraInteiro,
  tamanhoAdicionado: paraInteiro,
  bytesEnviados: paraInteiro,
  tamanhoDestino: paraInteiro,
  qtdAvisos: paraInteiro,
  qtdErros: paraInteiro,
};

export function extrairCampos(json: unknown): ResultadoParse {
  const campos = {} as CamposExtraidos;
  const diagnostico: DiagnosticoCampo[] = [];
  const naoEncontrados: string[] = [];

  for (const chave of Object.keys(CAMINHOS) as (keyof CamposExtraidos)[]) {
    const achado = primeiro(json, [...CAMINHOS[chave]]);
    const convertido = achado ? CONVERSORES[chave](achado.valor) : null;

    // @ts-expect-error — cada conversor devolve o tipo certo da sua chave;
    // o TypeScript não consegue provar isso pelo mapa genérico.
    campos[chave] = convertido;

    diagnostico.push({
      campo: chave,
      caminhoEncontrado: achado?.caminho ?? null,
      valorBruto: achado?.valor ?? null,
      valorConvertido: convertido,
    });

    // Só conta como "não encontrado" quando o campo não existe no JSON.
    // Existir e não converter é outro problema, visível no diagnóstico.
    if (!achado) naoEncontrados.push(chave);
  }

  return { campos, diagnostico, naoEncontrados };
}
