import { Router } from 'express';
import { extrairCampos } from '../duplicati/parse';
import { ultimosRelatorios, ultimasRecusas } from '../db/repo';

export const rotaCalibracao = Router();

/**
 * MODO CALIBRAÇÃO
 *
 * Mostra o que chegou de verdade, para conferir se o parser está lendo os
 * campos certos antes de confiar no painel.
 *
 * O uso é: dispare um backup de teste no Duplicati piloto, abra esta rota e
 * compare `valorBruto` com `valorConvertido` em cada campo. Se algum campo
 * aparecer com `caminhoEncontrado: null`, o nome dele mudou nessa versão do
 * Duplicati e o lugar de corrigir é `src/duplicati/parse.ts`.
 *
 * Como o JSON bruto foi guardado, o diagnóstico abaixo é recalculado na hora
 * a partir do original — então dá para corrigir o parser e recarregar esta
 * página para ver o efeito, sem precisar rodar outro backup.
 *
 * NOTA DE SEGURANÇA: esta rota não tem autenticação, e mostra o conteúdo dos
 * relatórios, que inclui caminhos de pastas dos servidores dos cartórios. Ela
 * é para uso local durante a calibração. Antes de expor o painel na internet,
 * ela precisa ficar atrás do login de admin (previsto no MVP) ou ser removida.
 */
rotaCalibracao.get('/api/calibracao', (_req, res) => {
  const relatorios = ultimosRelatorios(10).map((linha) => {
    const bruto = String(linha.json_bruto ?? '');

    let json: unknown = null;
    let erroLeitura: string | null = null;
    try {
      json = JSON.parse(bruto);
    } catch (e) {
      erroLeitura = e instanceof Error ? e.message : String(e);
    }

    const analise = json !== null ? extrairCampos(json) : null;

    return {
      id: linha.id,
      cliente: `${linha.cliente_nome} (${linha.cliente_cidade})`,
      recebidoEm: linha.recebido_em,
      versaoParserGravada: linha.versao_parser,

      colunasGravadas: {
        resultado: linha.resultado,
        operacao: linha.operacao,
        inicioEm: linha.inicio_em,
        fimEm: linha.fim_em,
        duracaoSegundos: linha.duracao_segundos,
        tamanhoOrigem: linha.tamanho_origem,
        tamanhoAdicionado: linha.tamanho_adicionado,
        bytesEnviados: linha.bytes_enviados,
        tamanhoDestino: linha.tamanho_destino,
        qtdAvisos: linha.qtd_avisos,
        qtdErros: linha.qtd_erros,
      },

      // Releitura do bruto com o parser ATUAL. Se divergir das colunas
      // gravadas, é sinal de que o parser mudou depois deste relatório
      // ter chegado — e de que vale reprocessar o histórico.
      analiseAtual: analise
        ? { naoEncontrados: analise.naoEncontrados, diagnostico: analise.diagnostico }
        : null,

      erroLeitura,
      jsonBruto: json,
    };
  });

  res.json({
    recebidos: relatorios.length,
    relatorios,
    recusados: ultimasRecusas(10),
  });
});
