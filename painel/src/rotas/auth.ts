import { Router } from 'express';
import { conferir } from '../auth/senha';
import {
  abrirSessao,
  conferirOrigem,
  fecharSessao,
  limparFalhas,
  podeTentar,
  registrarFalha,
} from '../auth/sessao';
import { buscarAdmin, contarAdmins, marcarAcesso } from '../db/repo';
import { telaLogin, telaSemAdmin } from '../views/login';

export const rotaAuth = Router();

/**
 * Só aceita destinos internos.
 *
 * Sem esta checagem, `/entrar?destino=https://site-falso/` faria o painel
 * redirecionar para fora depois do login — um golpe de phishing clássico,
 * porque o link partiu de um domínio em que a pessoa confia.
 */
function destinoSeguro(valor: unknown): string {
  if (typeof valor !== 'string' || valor === '') return '/';
  // Precisa começar com uma única barra. "//outro-site.com" é um endereço
  // absoluto disfarçado que o navegador segue para fora.
  if (!valor.startsWith('/') || valor.startsWith('//')) return '/';
  if (valor.includes('\\')) return '/';
  return valor;
}

/**
 * Lê um formulário HTML (application/x-www-form-urlencoded).
 *
 * O corpo chega como texto cru, porque o body parser global do painel é
 * `express.text()` — escolhido por causa do endpoint do Duplicati. Como só
 * dois formulários existem no sistema, interpretá-los aqui é mais simples do
 * que montar um segundo parser só para isso.
 */
export function lerFormulario(corpo: unknown): Record<string, string> {
  if (typeof corpo !== 'string' || corpo === '') return {};
  const p = new URLSearchParams(corpo);
  const saida: Record<string, string> = {};
  for (const [k, v] of p) saida[k] = v;
  return saida;
}

rotaAuth.get('/entrar', (req, res) => {
  if (contarAdmins() === 0) {
    return res.status(503).type('html').send(telaSemAdmin());
  }

  // Já está logado: não faz sentido mostrar a tela de entrada de novo.
  if (req.sessao) return res.redirect('/');

  const destino = destinoSeguro(req.query.destino);
  return res.type('html').send(
    telaLogin({ destino: destino === '/' ? undefined : destino }),
  );
});

rotaAuth.post('/entrar', conferirOrigem, (req, res) => {
  const dados = lerFormulario(req.body);
  const usuario = (dados.usuario ?? '').trim();
  const senha = dados.senha ?? '';
  const destino = destinoSeguro(dados.destino);
  const ip = req.ip ?? 'desconhecido';

  if (contarAdmins() === 0) {
    return res.status(503).type('html').send(telaSemAdmin());
  }

  const limite = podeTentar(ip);
  if (!limite.pode) {
    const min = Math.ceil(limite.faltamSegundos / 60);
    return res.status(429).type('html').send(
      telaLogin({
        erro: `Muitas tentativas. Aguarde ${min} minuto${min === 1 ? '' : 's'} e tente de novo.`,
        destino: destino === '/' ? undefined : destino,
      }),
    );
  }

  const admin = usuario ? buscarAdmin(usuario) : undefined;

  // Usuário errado e senha errada dão exatamente a mesma resposta. Dizer
  // "usuário não existe" entregaria de graça quais nomes de usuário são
  // válidos, e um atacante passaria a testar senhas só nos que existem.
  const ok = admin ? conferir(senha, { hash: admin.senha_hash, sal: admin.senha_sal }) : false;

  if (!ok || !admin) {
    registrarFalha(ip);
    console.warn(`login recusado — usuário "${usuario}" — ip ${ip}`);
    return res.status(401).type('html').send(
      telaLogin({
        erro: 'Usuário ou senha incorretos.',
        usuario,
        destino: destino === '/' ? undefined : destino,
      }),
    );
  }

  limparFalhas(ip);
  abrirSessao(req, res, admin.id);
  marcarAcesso(admin.id);
  console.log(`login: ${admin.usuario} — ip ${ip}`);

  return res.redirect(destino);
});

rotaAuth.post('/sair', conferirOrigem, (req, res) => {
  fecharSessao(req, res);
  res.redirect('/entrar');
});
