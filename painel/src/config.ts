import path from 'node:path';

/**
 * Configuração do painel, lida do ambiente com valores padrão que funcionam
 * sem nenhum .env — para o MVP rodar com `npm run dev` e mais nada.
 */

function inteiro(valor: string | undefined, padrao: number): number {
  if (!valor) return padrao;
  const n = Number.parseInt(valor, 10);
  return Number.isFinite(n) ? n : padrao;
}

export const config = {
  porta: inteiro(process.env.PORT, 3000),

  /**
   * Onde fica o arquivo do banco.
   *
   * O padrão é a pasta `dados/` do projeto. IMPORTANTE: nunca aponte isto
   * para uma pasta de rede ou OneDrive sincronizado. O SQLite depende de
   * travamento de arquivo, que não é confiável em SMB, e o banco corrompe.
   * Em Docker isto vira um volume; em produção, um caminho em disco local.
   */
  bancoCaminho:
    process.env.DB_PATH ?? path.resolve(process.cwd(), 'dados', 'painel.db'),

  /**
   * Limite de tamanho do corpo do POST do Duplicati.
   *
   * Um relatório normal tem alguns KB. Mas o Duplicati inclui as listas de
   * avisos e erros no JSON, e um backup com milhares de arquivos travados
   * pode gerar um relatório de vários MB. 5mb dá folga de sobra sem deixar
   * a porta aberta para alguém encher o disco com um POST gigante.
   */
  limiteCorpo: process.env.BODY_LIMIT ?? '5mb',

  /**
   * Fuso usado para MOSTRAR datas na tela. O banco guarda tudo em UTC.
   *
   * Rondônia é UTC-4 e não tem horário de verão. Usar o nome da zona em vez
   * de um deslocamento fixo é o certo: se a regra mudar por lei, o Node
   * acompanha pela base de fusos do sistema.
   */
  fusoExibicao: process.env.TZ_EXIBICAO ?? 'America/Porto_Velho',

  ambiente: process.env.NODE_ENV ?? 'development',
} as const;
