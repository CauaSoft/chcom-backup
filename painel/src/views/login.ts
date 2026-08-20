import { esc } from '../util/formato';

/**
 * Tela de entrada. Não usa o layout comum de propósito: quem não entrou
 * ainda não deve ver o menu de navegação do painel.
 */
export function telaLogin(opcoes: {
  erro?: string;
  aviso?: string;
  destino?: string;
  usuario?: string;
}): string {
  return `<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Entrar — Painel Backup CH.Com</title>
<style>
:root {
  --azul: #00A8FF; --azul-claro: #4CC3FF;
  --fundo: #14161C; --superficie: #1D2029; --borda: #2B3040;
  --texto: #E8EBF0; --texto2: #C0C6D1; --texto3: #8B93A3;
  --erro: #F3436B; --aviso: #F5A524;
}
* { box-sizing: border-box; }
body {
  margin: 0; min-height: 100vh;
  background: var(--fundo); color: var(--texto);
  font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
  display: grid; place-items: center; padding: 24px;
}
.caixa { width: 100%; max-width: 380px; }
.marca {
  display: flex; align-items: center; justify-content: center; gap: 12px;
  margin-bottom: 28px; font-size: 19px; font-weight: 600;
}
.marca .simbolo {
  width: 34px; height: 34px; border-radius: 8px;
  background: var(--azul); color: var(--fundo);
  display: grid; place-items: center; font-size: 14px; font-weight: 700;
}
.marca .sub { color: var(--texto3); font-weight: 400; }
form {
  background: var(--superficie); border: 1px solid var(--borda);
  border-radius: 12px; padding: 26px;
}
label {
  display: block; font-size: 13px; color: var(--texto2);
  margin-bottom: 7px; font-weight: 500;
}
input[type=text], input[type=password] {
  width: 100%; padding: 11px 13px; margin-bottom: 17px;
  background: var(--fundo); color: var(--texto);
  border: 1px solid var(--borda); border-radius: 7px;
  font-size: 15px; font-family: inherit;
}
input:focus { outline: none; border-color: var(--azul); }

/* A senha do painel é gerada e tem vinte caracteres com maiúscula, minúscula
   e número misturados. Digitar isso às cegas é onde a tentativa falha, e o
   erro que volta é o mesmo de senha errada — não há como saber que foi só um
   caractere trocado. Daí o olho. */
.campo-senha { position: relative; margin-bottom: 17px; }
.campo-senha input { margin-bottom: 0; padding-right: 46px; }
.olho {
  position: absolute; right: 6px; top: 50%; transform: translateY(-50%);
  width: 34px; height: 34px; padding: 0;
  background: transparent; border: none; border-radius: 6px;
  color: var(--texto3); cursor: pointer; font-size: 16px; line-height: 1;
  display: grid; place-items: center;
}
.olho:hover { color: var(--azul); background: var(--fundo); }

.capslock {
  display: none; align-items: center; gap: 7px;
  margin: 9px 0 0; font-size: 12.5px; color: var(--aviso);
}
.capslock.ligado { display: flex; }

button.entrar {
  width: 100%; padding: 12px; margin-top: 20px;
  /* Texto escuro sobre o azul: branco sobre #00A8FF dá 2,6:1 de contraste,
     abaixo do mínimo de 4,5:1 da WCAG. Escuro sobre o mesmo azul dá 8:1. */
  background: var(--azul); color: var(--fundo);
  border: none; border-radius: 7px;
  font-size: 15px; font-weight: 600; font-family: inherit; cursor: pointer;
}
button.entrar:hover { background: var(--azul-claro); }

.ajuda {
  margin: 16px 0 0; font-size: 12.5px; color: var(--texto3); line-height: 1.7;
}
.ajuda summary { cursor: pointer; color: var(--texto2); }
.ajuda .passo { margin-top: 9px; }
.msg {
  padding: 11px 13px; border-radius: 7px; margin-bottom: 17px; font-size: 14px;
}
.msg.erro  { background: rgba(243,67,107,.12); color: var(--erro); border: 1px solid rgba(243,67,107,.3); }
.msg.aviso { background: rgba(245,165,36,.12); color: var(--aviso); border: 1px solid rgba(245,165,36,.3); }
.rodape { text-align: center; color: var(--texto3); font-size: 12.5px; margin-top: 20px; }
/* Código veste tom de texto, não a cor da marca: azul aqui compete com o
   botão Entrar, que é a única coisa nesta tela que deve puxar o olho. */
code {
  font-family: 'Cascadia Mono', Consolas, monospace; font-size: 12.5px;
  background: var(--fundo); border: 1px solid var(--borda);
  border-radius: 4px; padding: 2px 6px; color: var(--texto2);
}
</style>
</head>
<body>
<div class="caixa">

  <div class="marca">
    <span class="simbolo">CH</span>
    <span>Painel Backup <span class="sub">CH.Com</span></span>
  </div>

  <form method="POST" action="/entrar">
    ${opcoes.destino ? `<input type="hidden" name="destino" value="${esc(opcoes.destino)}">` : ''}
    ${opcoes.erro ? `<div class="msg erro">${esc(opcoes.erro)}</div>` : ''}
    ${opcoes.aviso ? `<div class="msg aviso">${opcoes.aviso}</div>` : ''}

    <label for="usuario">Usuário</label>
    <input type="text" id="usuario" name="usuario" autocomplete="username"
           value="${esc(opcoes.usuario ?? '')}"${opcoes.usuario ? '' : ' autofocus'} required>

    <label for="senha">Senha</label>
    <div class="campo-senha">
      <input type="password" id="senha" name="senha"
             autocomplete="current-password"${opcoes.usuario ? ' autofocus' : ''} required>
      <button type="button" class="olho" id="olho"
              aria-label="Mostrar senha" title="Mostrar senha">&#128065;</button>
    </div>

    <p class="capslock" id="capslock">
      <span aria-hidden="true">&#9888;</span> Caps Lock está ligado
    </p>

    <button type="submit" class="entrar">Entrar</button>
  </form>

  <details class="ajuda">
    <summary>Não consigo entrar</summary>
    <div class="passo">
      A senha não pode ser recuperada — só trocada. No computador onde o painel
      está instalado, abra o Prompt de Comando e rode:
    </div>
    <div class="passo"><code>cd C:\\dev\\painel-backup-chcom</code></div>
    <div class="passo"><code>npm run definir-senha</code></div>
    <div class="passo">
      Ele pede uma senha nova e encerra as sessões abertas.
    </div>
  </details>

  <p class="rodape">CH.Com Soluções em Tecnologia</p>
</div>

<script>
(function () {
  var senha = document.getElementById('senha');
  var olho = document.getElementById('olho');
  var aviso = document.getElementById('capslock');

  olho.addEventListener('click', function () {
    var mostrando = senha.type === 'text';
    senha.type = mostrando ? 'password' : 'text';
    olho.setAttribute('aria-label', mostrando ? 'Mostrar senha' : 'Ocultar senha');
    olho.title = mostrando ? 'Mostrar senha' : 'Ocultar senha';
    olho.innerHTML = mostrando ? '&#128065;' : '&#128584;';
    senha.focus();
  });

  // Caps Lock ligado com senha que tem maiúscula e minúscula misturadas dá
  // exatamente o mesmo erro de senha errada, sem nenhuma pista do motivo.
  // getModifierState só responde durante um evento de teclado, então o aviso
  // aparece na primeira tecla e some quando desligam.
  function conferir(e) {
    if (typeof e.getModifierState !== 'function') return;
    aviso.classList.toggle('ligado', e.getModifierState('CapsLock'));
  }
  senha.addEventListener('keydown', conferir);
  senha.addEventListener('keyup', conferir);
  senha.addEventListener('blur', function () { aviso.classList.remove('ligado'); });
})();
</script>
</body>
</html>`;
}

/**
 * Mostrada quando ainda não existe nenhum admin no banco.
 *
 * O painel não cria um usuário padrão com senha conhecida — seria uma porta
 * aberta em toda instalação que alguém esquecesse de trocar. Em vez disso,
 * ele se recusa a funcionar até que a senha seja definida pelo terminal, que
 * é um lugar onde só quem tem acesso ao servidor chega.
 */
export function telaSemAdmin(): string {
  return telaLogin({
    aviso:
      'Nenhum administrador cadastrado ainda. No servidor, dentro da pasta do painel, rode <code>npm run definir-senha</code> — ele gera uma senha forte e mostra na tela uma única vez.',
  });
}
