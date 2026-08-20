import type { Cliente, ClienteCadastro } from '../db/repo';
import { esc, numero, tempoDesde } from '../util/formato';
import { pagina } from './layout';

/**
 * Tela de cadastro: criar cartórios e cuidar do que já existe.
 *
 * O QUE ESTA TELA PRECISA RESPONDER, NESTA ORDEM
 *
 *   1. "cadastrei — e agora, qual URL eu colo no Duplicati?"
 *   2. "colei lá; funcionou?"
 *   3. "errei o nome / o contrato encerrou / o token vazou"
 *
 * A versão anterior só respondia a primeira, e mal: a URL ficava escrita por
 * extenso em toda linha da tabela, sem botão de copiar. Isso deixava a coluna
 * ilegível E punha o token de TODOS os cartórios à mostra na tela — quem
 * passasse atrás da cadeira lia todos. Agora o token fica oculto e o que se
 * usa de verdade é o botão Copiar.
 */
export function telaCartorios(opcoes: {
  clientes: ClienteCadastro[];
  base: string;
  erro?: string;
  criado?: Cliente;
  excluido?: string;
  editado?: string;
  tokenNovo?: string;
  usuario?: string;
}): string {
  const { clientes, base } = opcoes;

  const nunca = clientes.filter((c) => c.total_relatorios === 0).length;

  const corpo = `
  <h1>Cadastro de cartórios</h1>
  <p class="legenda">
    ${numero(clientes.length)} cadastrado${clientes.length === 1 ? '' : 's'}${
      nunca > 0
        ? ` &middot; <span class="alerta">${numero(nunca)} nunca reportou${nunca === 1 ? '' : 'ram'}</span>`
        : ''
    }
  </p>

  ${opcoes.erro ? `<div class="msg erro">${esc(opcoes.erro)}</div>` : ''}

  ${
    opcoes.excluido
      ? `<div class="msg ok"><strong>${esc(opcoes.excluido)} foi excluído.</strong>
         <p>O histórico saiu do painel. Os backups na AWS não foram tocados.</p></div>`
      : ''
  }

  ${
    opcoes.editado
      ? `<div class="msg ok"><strong>${esc(opcoes.editado)} atualizado.</strong>
         <p>O token não mudou — o Duplicati do cartório continua reportando normalmente.</p></div>`
      : ''
  }

  ${
    opcoes.tokenNovo
      ? `<div class="msg atencao">
           <strong>Token novo gerado para ${esc(opcoes.tokenNovo)}.</strong>
           <p>O anterior parou de funcionar agora. Este cartório <strong>não vai mais
              reportar</strong> até alguém colar a URL nova no Duplicati dele.
              Copie a URL na tabela abaixo e leve para lá.</p>
         </div>`
      : ''
  }

  ${
    opcoes.criado
      ? `
  <div class="msg ok destaque">
    <strong>${esc(opcoes.criado.nome)} cadastrado.</strong>
    <p>Cole esta URL no <code>send-http-json-urls</code> do Duplicati dele:</p>
    <div class="url-nova">
      <code id="url-recem">${esc(base)}/api/report/${esc(opcoes.criado.token)}</code>
      <button type="button" class="btn-copiar" data-copiar="${esc(base)}/api/report/${esc(
        opcoes.criado.token,
      )}">Copiar</button>
    </div>
  </div>`
      : ''
  }

  <div class="tabela-area" style="padding:20px 22px;margin-bottom:32px">
    <form method="POST" action="/cartorios" class="form-linha">
      <div>
        <label for="nome">Nome do cartório</label>
        <input type="text" id="nome" name="nome" required maxlength="200"
               placeholder="1º Ofício de Registro Civil de Porto Velho">
      </div>
      <div>
        <label for="cidade">Cidade</label>
        <input type="text" id="cidade" name="cidade" required maxlength="120"
               placeholder="Porto Velho">
      </div>
      <div>
        <button type="submit">Cadastrar</button>
      </div>
    </form>
  </div>

  ${
    clientes.length === 0
      ? `<div class="vazio"><strong>Nenhum cartório ainda</strong>
         <p>Cadastre o primeiro no formulário acima.</p></div>`
      : `
  <div class="ferramentas">
    <input type="search" id="busca" placeholder="Buscar cartório ou cidade&hellip;"
           autocomplete="off" spellcheck="false">
  </div>

  <div class="tabela-area">
    <table id="tabela">
      <thead>
        <tr>
          <th>Cartório</th>
          <th>Reportando</th>
          <th>URL para o Duplicati</th>
          <th></th>
        </tr>
      </thead>
      <tbody>
        ${clientes.map((c) => linha(c, base)).join('\n')}
      </tbody>
    </table>
    <div class="sem-resultado" id="sem-resultado" hidden>Nenhum cartório com esse nome.</div>
  </div>`
  }

  <p class="rodape">
    <strong>Desativar</strong> faz o painel recusar novos relatórios, mas mantém
    todo o histórico &middot;
    <strong>Excluir</strong> apaga o cartório e o histórico dele, sem volta &middot;
    <strong>Novo token</strong> invalida o anterior e exige reconfigurar o
    Duplicati daquele cartório.
  </p>

  ${caixaEditar()}
  ${caixaExcluir()}
  ${caixaToken()}
  ${ESTILO}
  ${SCRIPT}`;

  return pagina({ titulo: 'Cadastro de cartórios', corpo, usuario: opcoes.usuario });
}

function linha(c: ClienteCadastro, base: string): string {
  const url = `${base}/api/report/${c.token}`;

  // Sinal de vida. "Nunca reportou" logo depois do cadastro é normal; depois
  // de um dia, é problema — e é a diferença que a pessoa precisa ver aqui,
  // sem ter de ir ao painel e voltar.
  const sinal =
    c.total_relatorios === 0
      ? '<span class="selo sem-dados"><span class="ponto"></span>nunca reportou</span>'
      : `<span class="selo ok"><span class="ponto"></span>${numero(c.total_relatorios)} relatório${
          c.total_relatorios === 1 ? '' : 's'
        }</span><div class="cidade">${esc(tempoDesde(c.ultimo_em))}</div>`;

  return `
        <tr class="ln${c.ativo ? '' : ' inativo'}"
            data-busca="${esc((c.nome + ' ' + c.cidade).toLowerCase())}">
          <td>
            <a href="/cartorio/${c.id}" class="nome-cartorio">${esc(c.nome)}</a>
            ${c.ativo ? '' : '<span class="cidade"> &middot; desativado</span>'}
            <div class="cidade">${esc(c.cidade)}</div>
          </td>
          <td>${sinal}</td>
          <td>
            <div class="url-linha">
              <button type="button" class="btn-copiar" data-copiar="${esc(url)}">Copiar</button>
              <button type="button" class="btn-ver" data-url="${esc(url)}">Ver</button>
              <code class="url-oculta" hidden>${esc(url)}</code>
            </div>
          </td>
          <td class="acoes">
            <button type="button" class="btn-secundario btn-editar"
                    data-id="${c.id}" data-nome="${esc(c.nome)}"
                    data-cidade="${esc(c.cidade)}">Editar</button>
            <form method="POST" action="/cartorios/${c.id}/situacao" style="display:inline">
              <input type="hidden" name="ativo" value="${c.ativo ? '0' : '1'}">
              <button type="submit" class="btn-secundario">${c.ativo ? 'Desativar' : 'Reativar'}</button>
            </form>
            <div class="menu">
              <button type="button" class="btn-mais" aria-label="Mais ações">&hellip;</button>
              <div class="menu-itens">
                <button type="button" class="btn-token" data-id="${c.id}"
                        data-nome="${esc(c.nome)}">Gerar token novo</button>
                <button type="button" class="btn-excluir" data-id="${c.id}"
                        data-nome="${esc(c.nome)}">Excluir cartório</button>
              </div>
            </div>
          </td>
        </tr>`;
}

function caixaEditar(): string {
  return `
  <div id="caixa-editar" class="modal" hidden>
    <form method="POST" class="modal-cx" id="form-editar">
      <h3 class="neutro">Editar cartório</h3>
      <p>Corrigir o nome ou a cidade. O token <strong>não muda</strong>, então o
         Duplicati do cartório continua reportando normalmente.</p>
      <label for="ed-nome">Nome</label>
      <input type="text" id="ed-nome" name="nome" required maxlength="200">
      <label for="ed-cidade">Cidade</label>
      <input type="text" id="ed-cidade" name="cidade" required maxlength="120">
      <div class="modal-botoes">
        <button type="button" class="btn-secundario" data-fechar>Cancelar</button>
        <button type="submit" class="btn-principal">Salvar</button>
      </div>
    </form>
  </div>`;
}

function caixaExcluir(): string {
  return `
  <div id="caixa-excluir" class="modal" hidden>
    <form method="POST" class="modal-cx" id="form-excluir">
      <h3>Excluir cartório</h3>
      <p>Isto apaga <strong id="ex-nome"></strong> e <strong>todo o histórico de
         backups</strong> dele deste painel. Não tem volta.</p>
      <p class="modal-nota">Os backups do cartório na AWS não são tocados — some o
         registro aqui, não o backup lá.</p>
      <label for="ex-confirmacao">Digite o nome do cartório para confirmar:</label>
      <input type="text" id="ex-confirmacao" name="confirmacao" autocomplete="off"
             spellcheck="false" placeholder="nome exato do cartório">
      <div class="modal-botoes">
        <button type="button" class="btn-secundario" data-fechar>Cancelar</button>
        <button type="submit" class="btn-perigo" id="ex-confirmar" disabled>Excluir para sempre</button>
      </div>
    </form>
  </div>`;
}

function caixaToken(): string {
  return `
  <div id="caixa-token" class="modal" hidden>
    <form method="POST" class="modal-cx" id="form-token">
      <h3 class="atencao">Gerar token novo</h3>
      <p>Um token novo para <strong id="tk-nome"></strong>. O atual para de
         funcionar <strong>na hora</strong>.</p>
      <p class="modal-nota">
        Use quando o token vazou. Depois disso o cartório <strong>não reporta mais</strong>
        até alguém ir ao Duplicati dele e colar a URL nova no
        <code>send-http-json-urls</code>. Como o backup roda de madrugada, um
        esquecimento aqui só aparece amanhã.
      </p>
      <div class="modal-botoes">
        <button type="button" class="btn-secundario" data-fechar>Cancelar</button>
        <button type="submit" class="btn-atencao">Gerar token novo</button>
      </div>
    </form>
  </div>`;
}

const ESTILO = `
  <style>
    .alerta { color:var(--aviso); }

    .form-linha { display:grid; grid-template-columns:2fr 1fr auto; gap:14px; align-items:end; }
    .form-linha label { display:block; font-size:13px; color:var(--texto2); margin-bottom:6px; }
    .form-linha input {
      width:100%; padding:10px 12px; background:var(--fundo); color:var(--texto);
      border:1px solid var(--borda); border-radius:7px; font-size:14px; font-family:inherit;
    }
    .form-linha input:focus { outline:none; border-color:var(--azul); }
    .form-linha button {
      padding:10px 22px; background:var(--azul); color:var(--fundo); border:none;
      border-radius:7px; font-size:14px; font-weight:600; font-family:inherit;
      cursor:pointer; white-space:nowrap;
    }
    .form-linha button:hover { background:var(--azul-claro); }

    .msg { padding:14px 16px; border-radius:9px; margin-bottom:20px; font-size:14px; }
    .msg p { margin:8px 0 0; color:var(--texto2); line-height:1.6; }
    .msg.erro { background:rgba(243,67,107,.12); color:var(--erro); border:1px solid rgba(243,67,107,.3); }
    .msg.ok   { background:rgba(34,197,94,.10); color:var(--texto2); border:1px solid rgba(34,197,94,.3); }
    .msg.ok strong { color:var(--ok); }
    .msg.atencao { background:rgba(245,165,36,.10); color:var(--texto2); border:1px solid rgba(245,165,36,.32); }
    .msg.atencao strong { color:var(--aviso); }
    .url-nova { display:flex; align-items:center; gap:10px; margin-top:10px; flex-wrap:wrap; }
    .url-nova code { background:var(--fundo); border:1px solid var(--borda); border-radius:6px;
                     padding:9px 12px; font-size:12.5px; color:var(--texto2); word-break:break-all; }

    .ferramentas { margin-bottom:14px; }
    #busca { width:100%; max-width:420px; padding:9px 13px; background:var(--fundo);
             color:var(--texto); border:1px solid var(--borda); border-radius:7px;
             font-size:14px; font-family:inherit; }
    #busca:focus { outline:none; border-color:var(--azul); }
    #tabela tr.ln.oculta { display:none; }
    #tabela tr.ln.inativo { opacity:.55; }
    .sem-resultado { padding:30px; text-align:center; color:var(--texto2); font-size:14px; }

    /* A URL fica OCULTA por padrão. Ela carrega o token, que é o que autentica
       o cartório: deixar as cem à mostra numa tabela põe todas na tela para
       quem passar atrás da cadeira. O que se usa de verdade é o Copiar. */
    .url-linha { display:flex; align-items:center; gap:7px; flex-wrap:wrap; }
    .url-oculta { background:var(--fundo); border:1px solid var(--borda); border-radius:6px;
                  padding:6px 10px; font-size:12px; color:var(--texto2); word-break:break-all; }
    .btn-copiar, .btn-ver {
      padding:6px 13px; background:transparent; color:var(--texto2);
      border:1px solid var(--borda); border-radius:6px; font-size:13px;
      font-family:inherit; cursor:pointer; white-space:nowrap;
    }
    .btn-copiar:hover, .btn-ver:hover { border-color:var(--azul); color:var(--azul); }
    .btn-copiar.feito { border-color:var(--ok); color:var(--ok); }

    .acoes { text-align:right; white-space:nowrap; }
    .btn-secundario {
      padding:6px 13px; background:transparent; color:var(--texto2);
      border:1px solid var(--borda); border-radius:6px; font-size:13px;
      font-family:inherit; cursor:pointer; white-space:nowrap; margin-left:6px;
    }
    .btn-secundario:hover { border-color:var(--azul); color:var(--azul); }

    /* As ações que não têm volta ficam atrás do "…": não devem estar a um
       clique de distância junto com as do dia a dia. */
    .menu { position:relative; display:inline-block; margin-left:6px; }
    .btn-mais { padding:6px 11px; background:transparent; color:var(--texto3);
                border:1px solid var(--borda); border-radius:6px; font-size:13px;
                font-family:inherit; cursor:pointer; line-height:1; }
    .btn-mais:hover { border-color:var(--azul); color:var(--azul); }
    .menu-itens { position:absolute; right:0; top:calc(100% + 5px); z-index:50;
                  background:var(--superficie); border:1px solid var(--borda);
                  border-radius:8px; padding:5px; min-width:190px; display:none;
                  box-shadow:0 10px 28px rgba(0,0,0,.45); }
    .menu.aberto .menu-itens { display:block; }
    .menu-itens button { display:block; width:100%; text-align:left; background:transparent;
                         border:none; color:var(--texto2); padding:9px 11px; border-radius:6px;
                         font-size:13px; font-family:inherit; cursor:pointer; white-space:nowrap; }
    .menu-itens button:hover { background:var(--fundo); color:var(--texto); }
    .menu-itens .btn-excluir:hover { color:var(--erro); }
    .menu-itens .btn-token:hover { color:var(--aviso); }

    .modal { position:fixed; inset:0; z-index:900; background:rgba(0,0,0,.72);
             display:flex; align-items:center; justify-content:center; padding:22px; }
    .modal[hidden] { display:none; }
    .modal-cx { background:var(--superficie); border:1px solid var(--borda);
                border-radius:12px; padding:24px; width:100%; max-width:490px; }
    .modal-cx h3 { margin:0 0 12px; font-size:17px; color:var(--erro); }
    .modal-cx h3.neutro { color:var(--texto); }
    .modal-cx h3.atencao { color:var(--aviso); }
    .modal-cx p { margin:0 0 10px; font-size:14px; color:var(--texto2); line-height:1.6; }
    .modal-nota { font-size:12.5px !important; color:var(--texto3) !important; }
    .modal-cx label { display:block; font-size:13px; color:var(--texto2); margin:16px 0 6px; }
    .modal-cx input { width:100%; padding:10px 12px; background:var(--fundo);
                      color:var(--texto); border:1px solid var(--borda);
                      border-radius:7px; font-size:14px; font-family:inherit; }
    .modal-cx input:focus { outline:none; border-color:var(--azul); }
    .modal-botoes { display:flex; gap:10px; justify-content:flex-end; margin-top:20px; }
    .btn-principal { padding:10px 18px; background:var(--azul); color:var(--fundo); border:none;
                     border-radius:7px; font-size:14px; font-weight:600;
                     font-family:inherit; cursor:pointer; }
    .btn-perigo { padding:10px 18px; background:var(--erro); color:#fff; border:none;
                  border-radius:7px; font-size:14px; font-weight:600;
                  font-family:inherit; cursor:pointer; }
    .btn-perigo:disabled { background:#3A2530; color:#7A5A65; cursor:not-allowed; }
    .btn-atencao { padding:10px 18px; background:var(--aviso); color:var(--fundo); border:none;
                   border-radius:7px; font-size:14px; font-weight:600;
                   font-family:inherit; cursor:pointer; }

    @media (max-width:820px) {
      .form-linha { grid-template-columns:1fr; }
      .acoes { text-align:left; }
    }
  </style>`;

const SCRIPT = `
  <script>
  (function () {
    // --- copiar ---------------------------------------------------------
    // O painel roda em localhost, que é contexto seguro, então a área de
    // transferência funciona. Se um dia for servido por http num domínio,
    // ela é bloqueada — daí o plano B de selecionar o texto.
    function copiar(botao) {
      var texto = botao.dataset.copiar;
      function pronto() {
        var antes = botao.textContent;
        botao.textContent = 'Copiado';
        botao.classList.add('feito');
        setTimeout(function () {
          botao.textContent = antes; botao.classList.remove('feito');
        }, 1600);
      }
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(texto).then(pronto, function () { manual(botao); });
      } else { manual(botao); }
    }
    function manual(botao) {
      var linha = botao.closest('td') || botao.parentElement;
      var codigo = linha.querySelector('code');
      if (!codigo) return;
      codigo.hidden = false;
      var faixa = document.createRange();
      faixa.selectNodeContents(codigo);
      var sel = window.getSelection();
      sel.removeAllRanges(); sel.addRange(faixa);
      botao.textContent = 'Ctrl+C';
    }

    document.addEventListener('click', function (e) {
      var b = e.target.closest('.btn-copiar');
      if (b) { copiar(b); return; }

      var v = e.target.closest('.btn-ver');
      if (v) {
        var codigo = v.parentElement.querySelector('.url-oculta');
        codigo.hidden = !codigo.hidden;
        v.textContent = codigo.hidden ? 'Ver' : 'Ocultar';
        return;
      }

      var mais = e.target.closest('.btn-mais');
      var abertos = document.querySelectorAll('.menu.aberto');
      Array.prototype.forEach.call(abertos, function (m) {
        if (!mais || m !== mais.parentElement) m.classList.remove('aberto');
      });
      if (mais) { mais.parentElement.classList.toggle('aberto'); return; }
    });

    // --- caixas ---------------------------------------------------------
    function abrir(id) { document.getElementById(id).hidden = false; }
    function fecharTodas() {
      Array.prototype.forEach.call(document.querySelectorAll('.modal'), function (m) {
        m.hidden = true;
      });
    }
    document.addEventListener('click', function (e) {
      if (e.target.hasAttribute && e.target.hasAttribute('data-fechar')) fecharTodas();
      if (e.target.classList && e.target.classList.contains('modal')) fecharTodas();
    });
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape') { fecharTodas(); }
    });

    // editar
    document.addEventListener('click', function (e) {
      var b = e.target.closest('.btn-editar');
      if (!b) return;
      document.getElementById('form-editar').action = '/cartorios/' + b.dataset.id + '/editar';
      document.getElementById('ed-nome').value = b.dataset.nome;
      document.getElementById('ed-cidade').value = b.dataset.cidade;
      abrir('caixa-editar');
      document.getElementById('ed-nome').focus();
    });

    // excluir: o botão só destrava com o nome digitado certo. A mesma
    // conferência é refeita no servidor.
    var alvoExcluir = '';
    var campoEx = document.getElementById('ex-confirmacao');
    var confirmarEx = document.getElementById('ex-confirmar');
    document.addEventListener('click', function (e) {
      var b = e.target.closest('.btn-excluir');
      if (!b) return;
      alvoExcluir = b.dataset.nome;
      document.getElementById('form-excluir').action = '/cartorios/' + b.dataset.id + '/excluir';
      document.getElementById('ex-nome').textContent = b.dataset.nome;
      campoEx.value = ''; confirmarEx.disabled = true;
      abrir('caixa-excluir');
      campoEx.focus();
    });
    campoEx.addEventListener('input', function () {
      confirmarEx.disabled = campoEx.value.trim() !== alvoExcluir.trim();
    });

    // token novo
    document.addEventListener('click', function (e) {
      var b = e.target.closest('.btn-token');
      if (!b) return;
      document.getElementById('form-token').action = '/cartorios/' + b.dataset.id + '/token';
      document.getElementById('tk-nome').textContent = b.dataset.nome;
      abrir('caixa-token');
    });

    // --- busca ----------------------------------------------------------
    var busca = document.getElementById('busca');
    if (busca) {
      var corpo = document.querySelector('#tabela tbody');
      var semResultado = document.getElementById('sem-resultado');
      busca.addEventListener('input', function () {
        var termo = busca.value.trim().toLowerCase();
        var visiveis = 0;
        Array.prototype.forEach.call(corpo.rows, function (tr) {
          var mostra = !termo || tr.dataset.busca.indexOf(termo) !== -1;
          tr.classList.toggle('oculta', !mostra);
          if (mostra) visiveis++;
        });
        semResultado.hidden = visiveis > 0;
      });
    }
  })();
  </script>`;

export { numero };
