import express from 'express';
import { config } from './config';
import { aplicarSchema } from './db';
import { contarAdmins } from './db/repo';
import {
  agendarLimpezaDeSessoes,
  carregarSessao,
  exigirLogin,
} from './auth/sessao';
import { rotaAuth } from './rotas/auth';
import { rotaRelatorio } from './rotas/relatorio';
import { rotaCofre } from './rotas/cofre';
import { rotaCalibracao } from './rotas/calibracao';
import { rotaPaginas } from './rotas/paginas';
import { pagina } from './views/layout';

const app = express();

// Atrás do proxy HTTPS de produção, isto faz o Express confiar no
// X-Forwarded-For para preencher req.ip e no X-Forwarded-Proto para
// req.protocol — que é o que decide se o cookie de sessão sai como Secure.
app.set('trust proxy', true);

// Não anunciar que o servidor é Express. Não é segurança de verdade, mas não
// há motivo para entregar de graça o alvo a quem varre a internet.
app.disable('x-powered-by');

/**
 * O corpo é lido como TEXTO, para qualquer Content-Type.
 *
 * O motivo está em src/rotas/relatorio.ts: se dependêssemos do
 * express.json(), um Duplicati que mandasse outro Content-Type teria seu
 * relatório descartado em silêncio. Num sistema cujo trabalho é avisar que
 * algo falhou, falhar em silêncio é o pior defeito possível.
 *
 * Os dois formulários do painel (login e cadastro) são interpretados à mão
 * pela função lerFormulario, em src/rotas/auth.ts.
 */
app.use(express.text({ type: '*/*', limit: config.limiteCorpo }));

// ---------------------------------------------------------------------------
// ROTAS PÚBLICAS — as únicas que funcionam sem login
// ---------------------------------------------------------------------------

/**
 * O endpoint do Duplicati fica FORA do login, e tem que ficar: o Duplicati
 * de cada cartório não faz login, ele se identifica pelo token na URL. É uma
 * autenticação diferente, não uma ausência de autenticação.
 */
app.use(rotaRelatorio);
app.use(rotaCofre);

app.get('/health', (_req, res) => {
  res.json({ ok: true, ambiente: config.ambiente });
});

// ---------------------------------------------------------------------------
// A PARTIR DAQUI, TUDO EXIGE LOGIN
// ---------------------------------------------------------------------------

app.use(carregarSessao);

// As telas de entrada e saída precisam da sessão carregada, mas não podem
// exigir login — senão não haveria como entrar.
app.use(rotaAuth);

app.use(exigirLogin);

app.use(rotaPaginas);
app.use(rotaCalibracao); // /api/calibracao, versão JSON

// ---------------------------------------------------------------------------

app.use((req, res) => {
  if (req.accepts('html')) {
    return res.status(404).type('html').send(
      pagina({
        titulo: 'Página não encontrada',
        usuario: req.sessao?.usuario,
        corpo: `<div class="vazio"><strong>Página não encontrada</strong>
                <p><a href="/">Voltar para o painel</a></p></div>`,
      }),
    );
  }
  return res.status(404).json({ ok: false, erro: 'rota não encontrada' });
});

app.use(
  (
    erro: Error,
    req: express.Request,
    res: express.Response,
    _next: express.NextFunction,
  ) => {
    console.error('erro não tratado:', erro);
    if (res.headersSent) return;

    // A mensagem do erro não vai para a tela: ela pode conter caminhos de
    // arquivo e detalhes internos. O log do servidor tem tudo.
    if (req.accepts('html')) {
      return res.status(500).type('html').send(
        pagina({
          titulo: 'Erro interno',
          corpo: `<div class="vazio"><strong>Erro interno</strong>
                  <p>Algo falhou no painel. Confira o log do servidor.</p></div>`,
        }),
      );
    }
    return res.status(500).json({ ok: false, erro: 'erro interno' });
  },
);

aplicarSchema();
agendarLimpezaDeSessoes();

app.listen(config.porta, () => {
  const semAdmin = contarAdmins() === 0;

  console.log('');
  console.log('  Painel Backup CH.Com');
  console.log(`  rodando em   http://localhost:${config.porta}`);
  console.log(`  banco        ${config.bancoCaminho}`);
  console.log('');

  if (semAdmin) {
    console.log('  ATENÇÃO: nenhum administrador cadastrado.');
    console.log('  O painel está bloqueado até você rodar:');
    console.log('');
    console.log('      npm run definir-senha');
    console.log('');
  }
});
