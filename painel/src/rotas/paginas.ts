import { Router, type Request } from 'express';
import {
  atualizarCliente,
  buscarClientePorId,
  criarCliente,
  definirAtivoCliente,
  excluirCliente,
  historicoDoCliente,
  listarClientesComSinal,
  mensagensDosRelatorios,
  regerarToken,
  resumoPainel,
  resumoPorDia,
  ultimasExecucoesDeTodos,
  ultimasRecusas,
  ultimosRelatorios,
} from '../db/repo';
import { ultimoSucessoPorItem, execucoesDoCofre } from '../db/repo';
import { conferirOrigem } from '../auth/sessao';
import { lerFormulario } from './auth';
import { extrairCampos } from '../duplicati/parse';
import { telaPainel } from '../views/painel';
import { telaCartorio } from '../views/cartorio';
import { telaCofre, type ExecucaoResumo } from '../views/cofre';
import { telaCartorios } from '../views/cartorios';
import { telaCalibracao, type ItemCalibracao } from '../views/calibracao';
import { pagina } from '../views/layout';

export const rotaPaginas = Router();

/**
 * Endereço base do painel, montado a partir do host da requisição.
 *
 * Não é fixado em `localhost`: assim, quando o painel estiver no servidor
 * Linux atrás do proxy HTTPS, as URLs mostradas na tela já saem corretas para
 * colar no Duplicati, sem ninguém precisar lembrar de trocar o domínio.
 */
function base(req: Request): string {
  return `${req.protocol}://${req.get('host') ?? 'localhost:3000'}`;
}

/**
 * Lê o :id da URL como número.
 *
 * O tipo de req.params permite string[] (o Express junta parâmetros
 * repetidos numa lista), então normalizar antes de converter evita que
 * "/cartorio/1/2" chegue como array e produza um NaN silencioso.
 */
function idDaUrl(valor: unknown): number {
  const texto = Array.isArray(valor) ? valor[0] : valor;
  if (typeof texto !== 'string') return NaN;
  return Number.parseInt(texto, 10);
}

function erroSimples(titulo: string, texto: string, usuario?: string): string {
  return pagina({
    titulo,
    usuario,
    corpo: `<div class="vazio"><strong>${titulo}</strong>
            <p>${texto}</p>
            <p><a href="/">Voltar para o painel</a></p></div>`,
  });
}

// ---------------------------------------------------------------------------
// PAINEL
/**
 * GET /cofre/:id
 *
 * A cópia externa daquele cartório. Separada da tela do backup por um motivo
 * de fundo: são dois produtos diferentes, com perguntas diferentes.
 *
 * A tela do backup responde "o último backup deu certo?". Esta responde "há
 * quanto tempo cada coisa não sobe?" — e a segunda pergunta é a que encontra
 * o buraco que a primeira não vê: uma execução recente bem-sucedida pode não
 * ter tocado numa VM parada há três meses.
 */
rotaPaginas.get('/cofre/:id', (req, res) => {
  const id = idDaUrl(req.params.id);

  if (!Number.isInteger(id) || id < 1) {
    return res
      .status(400)
      .type('html')
      .send(erroSimples('Endereço inválido', 'O número do cartório não é válido.', req.sessao?.usuario));
  }

  const cliente = buscarClientePorId(id);
  if (!cliente) {
    return res
      .status(404)
      .type('html')
      .send(erroSimples('Cartório não encontrado', `Não existe cartório com o número ${id}.`, req.sessao?.usuario));
  }

  const corpo = telaCofre({
    clienteNome: cliente.nome,
    clienteId: cliente.id,
    itens: ultimoSucessoPorItem(cliente.id),
    execucoes: execucoesDoCofre(cliente.id, 30) as ExecucaoResumo[],
  });

  return res
    .type('html')
    .send(pagina({ titulo: `Cofre — ${cliente.nome}`, corpo, usuario: req.sessao?.usuario }));
});

// ---------------------------------------------------------------------------

rotaPaginas.get('/', (req, res) => {
  res
    .type('html')
    .send(
      telaPainel(
        resumoPainel(),
        ultimasExecucoesDeTodos(),
        resumoPorDia(30),
        req.sessao?.usuario,
      ),
    );
});

rotaPaginas.get('/cartorio/:id', (req, res) => {
  const id = idDaUrl(req.params.id);

  if (!Number.isInteger(id) || id < 1) {
    return res
      .status(400)
      .type('html')
      .send(erroSimples('Endereço inválido', 'O número do cartório não é válido.', req.sessao?.usuario));
  }

  const cliente = buscarClientePorId(id);
  if (!cliente) {
    return res
      .status(404)
      .type('html')
      .send(erroSimples('Cartório não encontrado', `Não existe cartório com o número ${id}.`, req.sessao?.usuario));
  }

  const historico = historicoDoCliente(cliente.id, 200);
  const url = `${base(req)}/api/report/${cliente.token}`;

  // Busca o texto do erro só das execuções que tiveram erro ou aviso: o
  // json_bruto de um relatório pode ter vários MB, e carregar os 45 de um
  // cartório para mostrar duas mensagens seria caro à toa.
  const comProblema = historico
    .filter((h) => (h.qtd_erros ?? 0) > 0 || (h.qtd_avisos ?? 0) > 0)
    .map((h) => h.id);
  const mensagens = mensagensDosRelatorios(comProblema);

  return res
    .type('html')
    .send(telaCartorio(cliente, historico, url, mensagens, req.sessao?.usuario));
});

// ---------------------------------------------------------------------------
// CADASTRO DE CARTÓRIOS
// ---------------------------------------------------------------------------

/** Lê um parâmetro da URL como texto. O Express devolve string[] quando o
 *  parâmetro vem repetido, e aí um `typeof === 'string'` cru descartaria em
 *  silêncio o aviso que a tela precisa mostrar. */
function textoDaConsulta(valor: unknown): string | undefined {
  const v = Array.isArray(valor) ? valor[0] : valor;
  return typeof v === 'string' && v !== '' ? v : undefined;
}

rotaPaginas.get('/cartorios', (req, res) => {
  res.type('html').send(
    telaCartorios({
      clientes: listarClientesComSinal(),
      base: base(req),
      // Os avisos vêm da URL porque as ações redirecionam para cá: assim um
      // F5 depois não reenvia o formulário nem repete a ação.
      excluido: textoDaConsulta(req.query.excluido),
      editado: textoDaConsulta(req.query.editado),
      tokenNovo: textoDaConsulta(req.query.token),
      usuario: req.sessao?.usuario,
    }),
  );
});

rotaPaginas.post('/cartorios', conferirOrigem, (req, res) => {
  const dados = lerFormulario(req.body);
  const nome = (dados.nome ?? '').trim();
  const cidade = (dados.cidade ?? '').trim();

  if (nome === '' || cidade === '') {
    return res.status(400).type('html').send(
      telaCartorios({
        clientes: listarClientesComSinal(),
        base: base(req),
        erro: 'Preencha o nome do cartório e a cidade.',
        usuario: req.sessao?.usuario,
      }),
    );
  }

  // Limite alinhado ao maxlength das colunas. Sem isso, um POST feito fora do
  // formulário poderia gravar um nome de megabytes e estourar o layout de
  // todas as telas que listam cartórios.
  if (nome.length > 200 || cidade.length > 120) {
    return res.status(400).type('html').send(
      telaCartorios({
        clientes: listarClientesComSinal(),
        base: base(req),
        erro: 'Nome ou cidade longos demais.',
        usuario: req.sessao?.usuario,
      }),
    );
  }

  const criado = criarCliente(nome, cidade);
  console.log(`cartório cadastrado: #${criado.id} ${criado.nome}`);

  return res.type('html').send(
    telaCartorios({
      clientes: listarClientesComSinal(),
      base: base(req),
      criado,
      usuario: req.sessao?.usuario,
    }),
  );
});

rotaPaginas.post('/cartorios/:id/situacao', conferirOrigem, (req, res) => {
  const id = idDaUrl(req.params.id);
  const dados = lerFormulario(req.body);
  const ativo = dados.ativo === '1';

  if (!Number.isInteger(id) || !buscarClientePorId(id)) {
    return res
      .status(404)
      .type('html')
      .send(erroSimples('Cartório não encontrado', 'Nada foi alterado.', req.sessao?.usuario));
  }

  definirAtivoCliente(id, ativo);
  console.log(`cartório #${id} ${ativo ? 'reativado' : 'desativado'}`);

  // Redireciona em vez de responder direto: assim, se a pessoa apertar F5
  // depois, o navegador recarrega a lista em vez de reenviar o formulário.
  return res.redirect('/cartorios');
});

/**
 * Excluir um cartório e todo o histórico dele. NÃO TEM VOLTA.
 *
 * Exige que o nome do cartório seja digitado no formulário e confere aqui, no
 * servidor. Um "tem certeza?" no navegador é confirmação de reflexo: quem
 * apertou por engano aperta de novo por engano. Digitar o nome obriga a olhar
 * qual cartório é — que é o erro que realmente acontece, excluir o vizinho da
 * linha de baixo.
 *
 * A conferência é no servidor de propósito: validação só no navegador não é
 * validação, é sugestão.
 */
/**
 * Corrigir nome e cidade. Não encosta no token: arrumar um erro de digitação
 * não pode derrubar o Duplicati do cartório.
 */
rotaPaginas.post('/cartorios/:id/editar', conferirOrigem, (req, res) => {
  const id = idDaUrl(req.params.id);
  const dados = lerFormulario(req.body);
  const cliente = Number.isInteger(id) ? buscarClientePorId(id) : undefined;

  if (!cliente) {
    return res
      .status(404)
      .type('html')
      .send(erroSimples('Cartório não encontrado', 'Nada foi alterado.', req.sessao?.usuario));
  }

  const nome = (dados.nome ?? '').trim();
  const cidade = (dados.cidade ?? '').trim();

  if (!nome || !cidade) {
    return res
      .status(400)
      .type('html')
      .send(
        erroSimples('Nada foi alterado', 'Nome e cidade não podem ficar vazios.', req.sessao?.usuario),
      );
  }

  atualizarCliente(id, nome, cidade);
  console.log(`cartório #${id} atualizado para "${nome}" (${cidade})`);
  return res.redirect('/cartorios?editado=' + encodeURIComponent(nome));
});

/**
 * Token novo. O anterior morre na hora — é esse o ponto, serve para quando
 * vazou. Mas o cartório para de reportar até alguém colar a URL nova lá, e a
 * tela seguinte precisa dizer isso em letras grandes: como o backup roda de
 * madrugada, um esquecimento aqui só aparece no dia seguinte.
 */
rotaPaginas.post('/cartorios/:id/token', conferirOrigem, (req, res) => {
  const id = idDaUrl(req.params.id);
  const cliente = Number.isInteger(id) ? buscarClientePorId(id) : undefined;

  if (!cliente) {
    return res
      .status(404)
      .type('html')
      .send(erroSimples('Cartório não encontrado', 'Nada foi alterado.', req.sessao?.usuario));
  }

  regerarToken(id);
  console.log(`cartório #${id} "${cliente.nome}": token REGERADO`);
  return res.redirect('/cartorios?token=' + encodeURIComponent(cliente.nome));
});

rotaPaginas.post('/cartorios/:id/excluir', conferirOrigem, (req, res) => {
  const id = idDaUrl(req.params.id);
  const dados = lerFormulario(req.body);
  const cliente = Number.isInteger(id) ? buscarClientePorId(id) : undefined;

  if (!cliente) {
    return res
      .status(404)
      .type('html')
      .send(erroSimples('Cartório não encontrado', 'Nada foi apagado.', req.sessao?.usuario));
  }

  const digitado = (dados.confirmacao ?? '').trim();
  if (digitado !== cliente.nome.trim()) {
    return res
      .status(400)
      .type('html')
      .send(
        erroSimples(
          'Nada foi apagado',
          `Para excluir "${cliente.nome}" é preciso digitar o nome exatamente como está cadastrado. ` +
            'Volte e tente de novo.',
          req.sessao?.usuario,
        ),
      );
  }

  const relatoriosApagados = excluirCliente(id);
  console.log(
    `cartório #${id} "${cliente.nome}" EXCLUÍDO com ${relatoriosApagados} relatório(s)`,
  );

  return res.redirect('/cartorios?excluido=' + encodeURIComponent(cliente.nome));
});

// ---------------------------------------------------------------------------
// CALIBRAÇÃO
// ---------------------------------------------------------------------------

rotaPaginas.get('/calibracao', (req, res) => {
  const itens: ItemCalibracao[] = ultimosRelatorios(10).map((linha) => {
    const bruto = String(linha.json_bruto ?? '');

    let json: unknown = null;
    let erroLeitura: string | null = null;
    try {
      json = JSON.parse(bruto);
    } catch (e) {
      erroLeitura = e instanceof Error ? e.message : String(e);
    }

    const analise = json !== null ? extrairCampos(json) : null;

    // Reindenta o JSON para leitura humana. O original continua intacto no
    // banco — isto é só apresentação.
    let bonito = bruto;
    if (json !== null) {
      try {
        bonito = JSON.stringify(json, null, 2);
      } catch {
        /* mantém o original */
      }
    }

    return {
      id: Number(linha.id),
      cliente: `${linha.cliente_nome} (${linha.cliente_cidade})`,
      recebidoEm: String(linha.recebido_em),
      diagnostico: analise?.diagnostico ?? [],
      naoEncontrados: analise?.naoEncontrados ?? [],
      jsonBruto: bonito,
      erroLeitura,
    };
  });

  const recusas = ultimasRecusas(15).map((r) => ({
    recebido_em: String(r.recebido_em),
    motivo: String(r.motivo),
    token_usado: r.token_usado === null ? null : String(r.token_usado),
    ip_origem: r.ip_origem === null ? null : String(r.ip_origem),
  }));

  res.type('html').send(
    telaCalibracao({ itens, recusas, usuario: req.sessao?.usuario }),
  );
});
