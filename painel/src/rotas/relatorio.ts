import { Router, type Request } from 'express';
import { extrairCampos, VERSAO_PARSER } from '../duplicati/parse';
import {
  buscarClientePorToken,
  registrarRecusa,
  salvarRelatorio,
} from '../db/repo';

export const rotaRelatorio = Router();

/**
 * Formato esperado do token: 32 caracteres hexadecimais, como gerado em
 * `gerarToken()`. Validar o formato antes de consultar o banco descarta lixo
 * e varredura automática sem nem tocar no disco.
 */
const FORMATO_TOKEN = /^[0-9a-f]{32}$/;

function ipDe(req: Request): string | null {
  // Atrás do proxy HTTPS que vai existir em produção, req.ip é o IP do proxy.
  // O X-Forwarded-For traz o real, mas é um cabeçalho que o cliente pode
  // forjar — serve para diagnóstico, nunca para decisão de segurança.
  const encaminhado = req.headers['x-forwarded-for'];
  if (typeof encaminhado === 'string' && encaminhado.trim() !== '') {
    return encaminhado.split(',')[0]!.trim();
  }
  return req.ip ?? null;
}

/**
 * POST /api/report/:token
 *
 * É este endereço que vai no `send-http-json-urls` do Duplicati de cada
 * cartório. O Duplicati chama uma vez ao fim de cada execução de backup.
 *
 * O corpo chega como TEXTO CRU, não como JSON já interpretado pelo Express.
 * Isso é deliberado, por duas razões:
 *
 *   1. O `express.json()` só interpreta o corpo quando o Content-Type é
 *      `application/json`. Se alguma versão do Duplicati mandar outro
 *      cabeçalho, o corpo chegaria vazio e o relatório se perderia em
 *      silêncio — o pior tipo de falha num sistema de monitoramento.
 *
 *   2. Precisamos guardar o corpo EXATAMENTE como veio. Se o Express
 *      interpretasse e nós re-serializássemos, o texto gravado seria uma
 *      reconstrução, não o original, e perderíamos a capacidade de
 *      reprocessar com fidelidade.
 *
 * Por isso o corpo é lido inteiro como texto e interpretado aqui.
 */
rotaRelatorio.post('/api/report/:token', (req, res) => {
  const token = req.params.token ?? '';
  const ip = ipDe(req);
  const corpo = typeof req.body === 'string' ? req.body : '';

  // ---- 1. o token tem cara de token? -------------------------------------
  if (!FORMATO_TOKEN.test(token)) {
    registrarRecusa({
      tokenUsado: token.slice(0, 100),
      motivo: 'token com formato inválido',
      ipOrigem: ip,
      corpoBruto: corpo,
    });
    return res.status(401).json({ ok: false, erro: 'token inválido' });
  }

  // ---- 2. o token existe e está ativo? -----------------------------------
  const cliente = buscarClientePorToken(token);
  if (!cliente) {
    registrarRecusa({
      tokenUsado: token,
      motivo: 'token não cadastrado',
      ipOrigem: ip,
      corpoBruto: corpo,
    });
    return res.status(401).json({ ok: false, erro: 'token inválido' });
  }

  if (!cliente.ativo) {
    registrarRecusa({
      tokenUsado: token,
      motivo: `cliente desativado (${cliente.nome})`,
      ipOrigem: ip,
      corpoBruto: corpo,
    });
    return res.status(403).json({ ok: false, erro: 'cliente desativado' });
  }

  // ---- 3. o corpo é JSON? -------------------------------------------------
  if (corpo.trim() === '') {
    registrarRecusa({
      tokenUsado: token,
      motivo: 'corpo vazio',
      ipOrigem: ip,
      corpoBruto: null,
    });
    return res.status(400).json({ ok: false, erro: 'corpo vazio' });
  }

  let json: unknown;
  try {
    json = JSON.parse(corpo);
  } catch {
    registrarRecusa({
      tokenUsado: token,
      motivo: 'corpo não é JSON válido',
      ipOrigem: ip,
      corpoBruto: corpo,
    });
    return res.status(400).json({ ok: false, erro: 'corpo não é JSON válido' });
  }

  // ---- 4. extrair e guardar ----------------------------------------------
  //
  // A partir daqui não recusamos mais nada. Mesmo que o parser não reconheça
  // um único campo, o relatório é gravado: o json_bruto é o que importa
  // preservar, e as colunas podem ser preenchidas depois por reprocessamento.
  // Recusar um relatório porque o formato mudou seria jogar fora justamente
  // a evidência de que ele mudou.
  const { campos, diagnostico, naoEncontrados } = extrairCampos(json);

  const relatorioId = salvarRelatorio(
    cliente.id,
    campos,
    corpo,
    VERSAO_PARSER,
  );

  if (naoEncontrados.length > 0) {
    console.warn(
      `[relatorio ${relatorioId}] ${cliente.nome}: ${naoEncontrados.length} campo(s) não encontrado(s) no JSON: ${naoEncontrados.join(', ')}`,
    );
  }

  // O Duplicati ignora o corpo da resposta, mas ele é o que você vê ao testar
  // com curl — então vem completo o suficiente para conferir a leitura na hora.
  return res.status(200).json({
    ok: true,
    relatorioId,
    cliente: { id: cliente.id, nome: cliente.nome, cidade: cliente.cidade },
    campos,
    naoEncontrados,
    diagnostico,
  });
});
