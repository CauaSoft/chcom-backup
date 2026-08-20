/* ==========================================================================
   CH.Com Backup — histórico de execuções do backup

   O QUE ISTO RESOLVE

   O "N Versions" no cartão do backup é apenas um RÓTULO no Duplicati: clicar
   nele não faz nada além de selecionar a palavra. Mas é ali que a pessoa
   clica querendo saber o que está guardado e como foi cada execução.

   Aqui o rótulo vira botão e abre o histórico completo.

   DE ONDE VÊM OS DADOS, E POR QUE NÃO DO LUGAR ÓBVIO

   O caminho aparentemente natural seria /backup/{id}/filesets. Verificado num
   Duplicati real: ele devolve FileCount e FileSizes como -1 a menos que se
   peça a leitura completa do destino — e isso faz o Duplicati ir até a AWS a
   cada abertura da tela, o que é lento e custa dinheiro.

   /backup/{id}/log traz, em cada entrada do tipo Result, o relatório INTEIRO
   daquela execução: BytesUploaded, Duration, KnownFileSize e o resultado.
   Tudo do banco local, sem tocar na nuvem.

   COMO A TELA FOI DESENHADA

   A forma vem do trabalho que o leitor precisa fazer, nesta ordem:

     1. "Tem backup meu guardado?"  -> número em destaque no topo
     2. "Está rodando direito?"     -> colunas ao longo do tempo, uma por
                                       execução, com as falhas visíveis
     3. "O que houve na terça?"     -> a lista detalhada

   Decisões que seguem disso:

   - Uma cor só nas colunas (o azul da marca). A altura já carrega a
     magnitude; colorir por valor gastaria o único canal livre repetindo o
     que a barra já diz.
   - Status (êxito / aviso / falha) NUNCA por cor sozinha. Verde e amarelo
     têm separação ΔE 4,7 sob daltonismo protan — muito abaixo do mínimo
     seguro de 8, medido e não estimado. Por isso cada estado carrega ícone,
     palavra e cor: quem não distingue as cores lê o símbolo e o texto.
   - Grade fina, contínua e discreta; colunas magras com topo arredondado;
     rótulo só no extremo, nunca um número sobre cada coluna.
   - Texto sempre em tom de texto, nunca na cor do dado.

   Nada aqui altera backup, configuração ou arquivo: só leitura.
   ========================================================================== */

(function () {
  'use strict';

  var ESTILO_ID = 'chcom-versoes-estilo';
  var MODAL_ID = 'chcom-versoes-modal';

  var AZUL = '#00A8FF';
  var SUPERFICIE = '#1D2029';

  // --- formatação ---------------------------------------------------------

  function bytes(v, casasForcadas) {
    if (v === null || v === undefined || isNaN(v) || v < 0) return '—';
    if (v === 0) return '0 B';
    var u = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
    var i = Math.min(Math.floor(Math.log(Math.abs(v)) / Math.log(1024)), u.length - 1);
    var n = v / Math.pow(1024, i);
    var casas = casasForcadas !== undefined ? casasForcadas
              : (n < 10 && i > 0 ? 2 : n < 100 && i > 0 ? 1 : 0);
    return n.toLocaleString('pt-BR', {
      minimumFractionDigits: casas, maximumFractionDigits: casas
    }) + ' ' + u[i];
  }

  /* "00:00:01.2854076" ou "01:23:45" -> segundos.
     O Duplicati grava a duração como texto, não como número. */
  function duracaoEmSegundos(txt) {
    if (!txt || typeof txt !== 'string') return null;
    var p = txt.split(':');
    if (p.length !== 3) return null;
    var h = parseFloat(p[0]), m = parseFloat(p[1]), s = parseFloat(p[2]);
    if (isNaN(h) || isNaN(m) || isNaN(s)) return null;
    return h * 3600 + m * 60 + s;
  }

  function duracao(seg) {
    if (seg === null || seg === undefined || isNaN(seg) || seg < 0) return '—';
    if (seg < 1) return 'menos de 1 s';
    if (seg < 60) return Math.round(seg) + ' s';
    var h = Math.floor(seg / 3600);
    var m = Math.floor((seg % 3600) / 60);
    var s = Math.round(seg % 60);
    if (h > 0) return h + ' h ' + String(m).padStart(2, '0') + ' min';
    return m + ' min ' + String(s).padStart(2, '0') + ' s';
  }

  /* Rede se mede em BITS, arquivo em BYTES — daí o x8. É a confusão mais
     comum do ramo: um link de 100 Mbps entrega uns 12 MB/s. */
  function velocidade(bytesEnviados, segundos) {
    if (!bytesEnviados || !segundos || segundos <= 0) return '—';
    var bps = (bytesEnviados * 8) / segundos;
    var u = ['bps', 'Kbps', 'Mbps', 'Gbps'];
    var i = Math.min(Math.floor(Math.log(bps) / Math.log(1000)), u.length - 1);
    var n = bps / Math.pow(1000, i);
    return n.toLocaleString('pt-BR', {
      minimumFractionDigits: n < 10 ? 1 : 0, maximumFractionDigits: n < 10 ? 1 : 0
    }) + ' ' + u[i];
  }

  function quando(iso) {
    if (!iso) return '—';
    var d = new Date(iso);
    if (isNaN(d.getTime())) return '—';
    var hora = d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
    var hoje = new Date();
    var ontem = new Date(hoje.getTime() - 86400000);
    var dia = function (x) { return x.toDateString(); };
    if (dia(d) === dia(hoje)) return 'hoje às ' + hora;
    if (dia(d) === dia(ontem)) return 'ontem às ' + hora;
    return d.toLocaleDateString('pt-BR', {
      weekday: 'long', day: 'numeric', month: 'long', year: 'numeric'
    }) + ', ' + hora;
  }

  /* Data curta para a coluna da tabela. Por extenso ("quarta-feira, 12 de
     agosto de 2026, 20:40") a coluna passa de 300px e cada linha tem um
     comprimento diferente, o que atrapalha justamente o que a tabela serve
     para fazer: correr o olho de cima a baixo. "qua 12/08 20:40" tem sempre
     o mesmo tamanho. Hoje e ontem continuam por extenso porque são as
     únicas que a pessoa lê como referência de tempo, não como data. */
  function quandoCurto(iso) {
    if (!iso) return '—';
    var d = new Date(iso);
    if (isNaN(d.getTime())) return '—';
    var hora = d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
    var hoje = new Date();
    var ontem = new Date(hoje.getTime() - 86400000);
    if (d.toDateString() === hoje.toDateString()) return 'hoje ' + hora;
    if (d.toDateString() === ontem.toDateString()) return 'ontem ' + hora;
    var sem = d.toLocaleDateString('pt-BR', { weekday: 'short' }).replace('.', '');
    return sem + ' ' + d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' }) +
           ' ' + hora;
  }

  function dataCurta(iso) {
    var d = new Date(iso);
    if (isNaN(d.getTime())) return '';
    return d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' });
  }

  function escapar(t) {
    return String(t === null || t === undefined ? '' : t)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  /* Cada estado carrega ÍCONE + PALAVRA além da cor. Ver o cabeçalho do
     arquivo: a separação verde/amarelo sob daltonismo é insuficiente, então
     a cor nunca é o único portador da informação. */
  function situacao(r) {
    var s = String(r || '').toLowerCase();
    if (s === 'success') return { c: 'ok', icone: '✓', texto: 'realizado com êxito' };
    if (s === 'warning') return { c: 'aviso', icone: '!', texto: 'concluído com avisos' };
    if (s === 'error' || s === 'fatal') return { c: 'erro', icone: '✕', texto: 'falhou' };
    // Resultado desconhecido não é sucesso: pintar de verde algo que pode ter
    // falhado de um jeito novo é pior que admitir que não sabemos.
    return { c: 'aviso', icone: '?', texto: String(r || 'sem informação') };
  }

  /* Mensagens do relatório: limpa espaços, descarta vazias e guarda no
     máximo 8. O Duplicati pode devolver centenas quando um destino inteiro
     está fora do ar, e despejar tudo na tela não ajuda ninguém. */
  function linhas(lista) {
    var saida = [];
    (lista || []).forEach(function (t) {
      var s = String(t === null || t === undefined ? '' : t).replace(/\s+/g, ' ').trim();
      if (s && saida.indexOf(s) === -1) saida.push(s);
    });
    return saida.slice(0, 8);
  }

  /* --- o que o erro quer dizer ---------------------------------------------

     O Duplicati fala inglês e fala de dentro para fora: "The backend protocol
     s3-aws is not supported" não diz a quem está lendo que o problema está
     no endereço do destino, nem o que fazer. Cada entrada aqui traduz um erro
     que já apareceu de verdade nos cartórios para uma frase que aponta a
     causa. O texto original continua na tela, logo abaixo — a tradução é um
     acréscimo, nunca uma substituição, porque uma tradução errada num erro
     que eu não previ seria pior que nenhuma. */
  var EXPLICACOES = [
    { re: /protocol\s+["']?s3-aws/i,
      diz: 'O endereço do destino está começando com "s3-aws://". Esse protocolo não existe: ' +
           '"aws" é o valor da opção --s3-client, não o começo do endereço. O correto é "s3://".' },
    { re: /InvalidAccessKeyId|SignatureDoesNotMatch|AccessDenied|Access Denied|403/i,
      diz: 'A Amazon recusou as credenciais. A chave de acesso pode ter sido trocada, ' +
           'apagada ou perdido a permissão no bucket.' },
    { re: /No such host is known|NameResolutionFailure|Unable to connect|timed out|timeout/i,
      diz: 'O servidor não conseguiu chegar ao destino. Costuma ser internet fora, ' +
           'DNS ou firewall bloqueando a saída.' },
    { re: /not enough space|disk is full|espa[çc]o/i,
      diz: 'Faltou espaço em disco. O Duplicati precisa de espaço livre local para montar ' +
           'os blocos antes de enviar.' },
    { re: /database is locked|already running/i,
      diz: 'Outra execução deste mesmo backup ainda estava rodando.' },
    { re: /Found \d+ remote files that are not recorded|Missing file|not found in the remote/i,
      diz: 'O que está no destino não bate com o registro local. Costuma resolver com ' +
           'Reparar (Repair) na tela do backup.' },
    { re: /hash mismatch|checksum|corrupt/i,
      diz: 'Um arquivo chegou corrompido ao destino ou voltou diferente do que foi enviado.' },
    { re: /passphrase|decrypt/i,
      diz: 'Problema com a senha de criptografia do backup.' }
  ];

  function explicar(mensagens) {
    for (var i = 0; i < (mensagens || []).length; i++) {
      for (var j = 0; j < EXPLICACOES.length; j++) {
        if (EXPLICACOES[j].re.test(mensagens[i])) return EXPLICACOES[j].diz;
      }
    }
    return null;
  }

  // --- acesso à API -------------------------------------------------------

  /* DE ONDE VEM A AUTORIZAÇÃO — e por que não se pede um token novo

     O caminho óbvio seria POST /api/v1/auth/refresh. Duas razões para não:

     1. Ele exige um "nonce" que a tela do Duplicati guarda em
        sessionStorage["refreshNonce"] (ou localStorage, quando é "lembrar de
        mim"). Sem o nonce no corpo, o servidor responde 401 — foi o que
        derrubou a primeira versão desta tela.

     2. Pior: renovar GIRA o cookie e emite um nonce novo. Se o Duplicati não
        souber do novo, ele perde a sessão na renovação seguinte e o usuário é
        deslogado do nada — por culpa desta tela, que é só de leitura.

     Então não se pede nada. Escuta-se o cabeçalho Authorization que o próprio
     Duplicati já manda: ele consulta o servidor a todo momento (estado,
     progresso), e o token aparece sozinho. Zero token novo, zero risco. */

  var tokenVisto = null;

  function espiarToken() {
    // O Angular manda tudo por XMLHttpRequest; este é o caminho principal.
    var setOriginal = XMLHttpRequest.prototype.setRequestHeader;
    XMLHttpRequest.prototype.setRequestHeader = function (nome, valor) {
      try {
        if (String(nome).toLowerCase() === 'authorization' &&
            /^Bearer\s+\S/i.test(String(valor))) {
          tokenVisto = String(valor).replace(/^Bearer\s+/i, '');
        }
      } catch (e) { /* jamais atrapalhar a chamada do aplicativo */ }
      return setOriginal.apply(this, arguments);
    };

    var fetchOriginal = window.fetch;
    if (typeof fetchOriginal === 'function') {
      window.fetch = function (entrada, opcoes) {
        try {
          var h = opcoes && opcoes.headers, v = null;
          if (h) v = (typeof h.get === 'function') ? h.get('Authorization')
                                                  : (h.Authorization || h.authorization);
          if (v && /^Bearer\s+\S/i.test(String(v))) {
            tokenVisto = String(v).replace(/^Bearer\s+/i, '');
          }
        } catch (e) { }
        return fetchOriginal.apply(this, arguments);
      };
    }
  }

  function obterToken() {
    if (tokenVisto) return Promise.resolve(tokenVisto);
    // Espera curta: se a pessoa acabou de abrir a página, o aplicativo ainda
    // não consultou nada. Passado esse tempo, renova como último recurso.
    return new Promise(function (ok, falha) {
      var voltas = 0;
      var t = setInterval(function () {
        if (tokenVisto) { clearInterval(t); ok(tokenVisto); return; }
        if (++voltas > 8) { clearInterval(t); renovarToken().then(ok, falha); }
      }, 150);
    });
  }

  var NONCE_SESSAO = 'refreshNonce';
  var NONCE_LOCAL = 'v1:persist:duplicati:refreshNonce';

  /* Último recurso. Manda o nonce que o Duplicati guarda e DEVOLVE o nonce
     novo ao mesmo lugar de onde veio — sem isso a sessão quebraria depois. */
  function renovarToken() {
    var deSessao = null, deLocal = null;
    try { deSessao = sessionStorage.getItem(NONCE_SESSAO); } catch (e) { }
    try { deLocal = localStorage.getItem(NONCE_LOCAL); } catch (e) { }
    var nonce = deSessao || deLocal;

    return fetch('/api/v1/auth/refresh', {
      method: 'POST',
      credentials: 'include',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(nonce ? { Nonce: nonce } : {})
    })
      .then(function (r) {
        if (!r.ok) throw new Error('sessão expirada — atualize a página (F5)');
        return r.json();
      })
      .then(function (j) {
        if (j && j.Nonce) {
          try {
            if (deSessao) sessionStorage.setItem(NONCE_SESSAO, j.Nonce);
            else if (deLocal) localStorage.setItem(NONCE_LOCAL, j.Nonce);
          } catch (e) { }
        }
        tokenVisto = j.AccessToken;
        return tokenVisto;
      });
  }

  function api(caminho, jaTentou) {
    return obterToken().then(function (t) {
      return fetch(caminho, { headers: { Authorization: 'Bearer ' + t } })
        .then(function (r) {
          // Token vencido enquanto a tela estava aberta: descarta e pega o
          // próximo que o aplicativo mandar.
          if (r.status === 401 && !jaTentou) {
            tokenVisto = null;
            return api(caminho, true);
          }
          if (!r.ok) throw new Error('HTTP ' + r.status);
          return r.json();
        });
    });
  }

  function acharBackup(nomeVisivel) {
    return api('/api/v1/backups').then(function (lista) {
      var alvo = null;
      (lista || []).forEach(function (item) {
        var b = item.Backup || item;
        if (!b || !b.Name) return;
        // devolve o item inteiro: o agendamento vive fora de Backup
        if (nomeVisivel && nomeVisivel.indexOf(b.Name) !== -1) alvo = item;
      });
      if (!alvo && (lista || []).length === 1) alvo = lista[0];
      return alvo;
    });
  }

  /* Quando roda de novo. Vem do agendamento, não do histórico — um backup
     que falhou ontem e não tem próxima execução marcada é um backup parado,
     e essa é uma informação que só aparece aqui. */
  function proximaExecucao(item) {
    var s = item && (item.Schedule || (item.Backup && item.Backup.Schedule));
    if (!s || !s.Time) return null;
    var d = new Date(s.Time);
    if (isNaN(d.getTime())) return null;
    // O Duplicati grava ano 1 quando o agendamento está desligado.
    if (d.getFullYear() < 2000) return null;
    return quando(d.toISOString());
  }

  function execucoesDeBackup(log) {
    var saida = [];
    (log || []).forEach(function (e) {
      if (e.Type !== 'Result' || !e.Message) return;
      var m;
      try { m = JSON.parse(e.Message); } catch (x) { return; }
      if (!m || m.MainOperation !== 'Backup') return;

      var bs = m.BackendStatistics || {};
      saida.push({
        quando: m.EndTime || m.BeginTime ||
                (e.Timestamp ? new Date(e.Timestamp * 1000).toISOString() : null),
        resultado: m.ParsedResult,
        enviado: bs.BytesUploaded,
        noDestino: bs.KnownFileSize,
        origem: m.SizeOfExaminedFiles,
        segundos: duracaoEmSegundos(m.Duration),
        avisos: m.WarningsActualLength || 0,
        erros: m.ErrorsActualLength || 0,
        // O relatório carrega o texto do que deu errado. Sem isto a tela diz
        // "2 erros" e a pessoa tem de ir caçar no log qual foi — que é
        // exatamente o trabalho que esta tela existe para evitar.
        textoErros: linhas(m.Errors),
        textoAvisos: linhas(m.Warnings)
      });
    });
    saida.sort(function (a, b) { return new Date(b.quando) - new Date(a.quando); });
    return saida;
  }

  // --- gráfico ------------------------------------------------------------

  /* Colunas: uma execução por coluna, altura = quanto subiu.
     Mostra o padrão de uso da rede e faz as falhas saltarem, que é a
     pergunta "está rodando direito?".

     Feito em HTML e CSS, não em SVG. Um SVG com viewBox é escalado para a
     largura disponível, e com isso a coluna de 24px vira 30px numa janela
     larga e 18px numa estreita — a espessura passaria a depender do tamanho
     da tela em vez da especificação. Em HTML, 24px são 24px em qualquer
     largura, e só a ALTURA (que é o dado) varia. */
  /* Topo da escala num número redondo. Sem isso a grade sai marcada em
     "9 GB" e "5 GB" (o máximo mais uma folga), que é um número sem sentido
     para quem lê. Sobe até o próximo 1, 2 ou 5 vezes uma potência de 1024,
     de modo que a metade também caia num número limpo. */
  function topoRedondo(maximo) {
    var folga = maximo * 1.1;
    var unidade = Math.pow(1024, Math.floor(Math.log(folga) / Math.log(1024)));
    var passos = [1, 2, 5, 10, 20, 50, 100, 200, 500, 1024];
    for (var i = 0; i < passos.length; i++) {
      if (passos[i] * unidade >= folga) return passos[i] * unidade;
    }
    return folga;
  }

  function grafico(execucoes) {
    var dados = execucoes.slice(0, 14).reverse();   // mais antigo à esquerda
    if (dados.length < 2) return '';

    var maximo = Math.max.apply(null, dados.map(function (d) { return d.enviado || 0; }));
    if (maximo <= 0) return '';
    var topo = topoRedondo(maximo);

    // Grade: linhas finas, contínuas, um passo acima da superfície.
    var grade = [1, 0.5].map(function (f) {
      return '<div class="lin" style="bottom:' + (f * 100) + '%">' +
             '<span>' + escapar(bytes(topo * f, 0)) + '</span></div>';
    }).join('') + '<div class="lin base" style="bottom:0"></div>';

    var colunas = dados.map(function (d) {
      var v = d.enviado || 0;
      var pct = Math.max(1.5, (v / topo) * 100);
      var s = situacao(d.resultado);

      // A cor aqui é reforço, não o portador: a coluna baixa e o ícone na
      // lista já dizem que algo deu errado.
      var classe = s.c === 'erro' ? 'err' : (s.c === 'aviso' ? 'avi' : '');

      return '<div class="faixa" title="' +
             escapar(quando(d.quando) + ' — ' + bytes(d.enviado) + ' em ' + duracao(d.segundos)) +
             '"><div class="col ' + classe + '" style="height:' + pct.toFixed(1) + '%"></div></div>';
    }).join('');

    return '<div class="gr">' +
      '<div class="gr-t">Enviado por execução <span class="gr-s">últimas ' +
      dados.length + '</span></div>' +
      '<div class="plot">' + grade + '<div class="cols">' + colunas + '</div></div>' +
      // Rótulo só nos extremos: uma data sob cada coluna vira ruído.
      '<div class="eixo"><span>' + escapar(dataCurta(dados[0].quando)) + '</span>' +
      '<span>' + escapar(dataCurta(dados[dados.length - 1].quando)) + '</span></div>' +
      '</div>';
  }

  // --- interface ----------------------------------------------------------

  function injetarEstilo() {
    if (document.getElementById(ESTILO_ID)) return;
    var s = document.createElement('style');
    s.id = ESTILO_ID;
    s.textContent = [
      '.chcom-versoes-botao{cursor:pointer!important;user-select:none;transition:filter .15s}',
      '.chcom-versoes-botao:hover{filter:brightness(1.3)}',

      '#' + MODAL_ID + '{position:fixed;inset:0;z-index:99999;background:rgba(0,0,0,.7);',
      '  display:flex;align-items:center;justify-content:center;padding:24px;',
      '  font-family:"Segoe UI",system-ui,-apple-system,sans-serif}',
      '#' + MODAL_ID + ' .cx{background:' + SUPERFICIE + ';border:1px solid #2B3040;',
      '  border-radius:14px;width:100%;max-width:860px;max-height:88vh;',
      '  display:flex;flex-direction:column;color:#E8EBF0;overflow:hidden}',

      '#' + MODAL_ID + ' .cab{display:flex;align-items:center;gap:12px;padding:18px 24px;',
      '  border-bottom:1px solid #2B3040}',
      '#' + MODAL_ID + ' .cab h2{margin:0;font-size:16px;font-weight:600;letter-spacing:.2px}',
      '#' + MODAL_ID + ' .cab .sub{color:#8B93A3;font-size:13px;margin-top:1px}',
      '#' + MODAL_ID + ' .fechar{margin-left:auto;background:none;border:none;color:#8B93A3;',
      '  font-size:24px;line-height:1;cursor:pointer;padding:2px 6px;border-radius:6px}',
      '#' + MODAL_ID + ' .fechar:hover{color:#E8EBF0;background:#232734}',

      '#' + MODAL_ID + ' .corpo{overflow-y:auto;padding:22px 24px 24px}',

      // hero: o número que responde "tem backup meu guardado?"
      '#' + MODAL_ID + ' .hero{display:flex;align-items:flex-end;gap:26px;flex-wrap:wrap;',
      '  padding-bottom:20px;border-bottom:1px solid #2B3040;margin-bottom:20px}',
      '#' + MODAL_ID + ' .hero .r{color:#8B93A3;font-size:12px;margin-bottom:4px}',
      '#' + MODAL_ID + ' .hero .big{font-size:46px;font-weight:600;line-height:1;color:#E8EBF0}',
      '#' + MODAL_ID + ' .hero .lado{padding-bottom:5px}',
      '#' + MODAL_ID + ' .hero .lado .v{font-size:15px;font-weight:600}',

      // gráfico
      '#' + MODAL_ID + ' .gr{margin-bottom:26px}',
      '#' + MODAL_ID + ' .gr-t{color:#8B93A3;font-size:12px;margin-bottom:10px}',
      '#' + MODAL_ID + ' .gr-s{color:#5A616F;margin-left:6px}',
      '#' + MODAL_ID + ' .plot{position:relative;height:132px}',
      // grade: hairline sólida, um passo acima da superfície, recessiva
      '#' + MODAL_ID + ' .lin{position:absolute;left:0;right:0;height:1px;background:#2B3040}',
      '#' + MODAL_ID + ' .lin span{position:absolute;left:0;bottom:3px;color:#8B93A3;font-size:10px}',
      '#' + MODAL_ID + ' .lin.base{background:#3A4152}',
      '#' + MODAL_ID + ' .cols{position:absolute;inset:0;display:flex;align-items:flex-end;gap:2px}',
      // a faixa distribui o espaço; a coluna dentro dela tem largura fixa,
      // então a espessura não muda com o tamanho da janela
      '#' + MODAL_ID + ' .faixa{flex:1;height:100%;display:flex;align-items:flex-end;',
      '  justify-content:center;cursor:default}',
      '#' + MODAL_ID + ' .col{width:100%;max-width:24px;background:' + AZUL + ';',
      '  border-radius:3px 3px 0 0;transition:opacity .12s}',
      '#' + MODAL_ID + ' .col.avi{background:#F5A524}',
      '#' + MODAL_ID + ' .col.err{background:#F3436B}',
      '#' + MODAL_ID + ' .faixa:hover .col{opacity:.72}',
      '#' + MODAL_ID + ' .eixo{display:flex;justify-content:space-between;',
      '  color:#8B93A3;font-size:10px;margin-top:7px}',

      // tabela
      '#' + MODAL_ID + ' .lt{color:#8B93A3;font-size:12px;margin-bottom:10px}',
      '#' + MODAL_ID + ' .rolo{overflow-x:auto}',
      '#' + MODAL_ID + ' .tb{width:100%;border-collapse:collapse;font-size:13.5px}',
      '#' + MODAL_ID + ' .tb th{color:#8B93A3;font-size:11.5px;font-weight:500;',
      '  text-align:left;padding:0 12px 8px 0;border-bottom:1px solid #2B3040;white-space:nowrap}',
      // números à direita e com dígitos de largura igual: é o que deixa a
      // coluna comparável de cima a baixo
      '#' + MODAL_ID + ' .tb th.n,#' + MODAL_ID + ' .tb td.n{text-align:right;',
      '  font-variant-numeric:tabular-nums}',
      '#' + MODAL_ID + ' .tb td{padding:11px 12px 11px 0;border-bottom:1px solid #23273300;',
      '  border-top:1px solid #23272F;white-space:nowrap}',
      '#' + MODAL_ID + ' .tb tbody tr:first-child td{border-top:none}',
      '#' + MODAL_ID + ' .tb td.n{font-weight:600;color:#E8EBF0}',
      '#' + MODAL_ID + ' .tb td.n.fraco{color:#5A616F;font-weight:500}',
      '#' + MODAL_ID + ' .tb td.q{color:#C0C6D1;padding-right:18px}',
      '#' + MODAL_ID + ' .tag{background:#232734;color:#8B93A3;border-radius:4px;',
      '  padding:1px 6px;font-size:10.5px;margin-left:5px;vertical-align:1px}',
      '#' + MODAL_ID + ' .ln:hover td{background:#21252F}',
      // a linha de detalhe pertence à de cima: sem risco entre as duas
      '#' + MODAL_ID + ' .ln.com-det td{border-bottom:none}',
      '#' + MODAL_ID + ' .det td{border-top:none;padding:0 0 12px 0;white-space:normal}',

      // marca de estado: ícone + palavra; a cor é o terceiro sinal, nunca o único
      '#' + MODAL_ID + ' .est{display:inline-flex;align-items:center;gap:7px;',
      '  white-space:nowrap;color:#C0C6D1}',
      '#' + MODAL_ID + ' .est.erro{color:#F3436B;font-weight:600}',
      '#' + MODAL_ID + ' .est.aviso{color:#F5A524}',
      '#' + MODAL_ID + ' .ic{width:18px;height:18px;border-radius:50%;flex:none;',
      '  display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:700}',
      '#' + MODAL_ID + ' .ic.ok{background:rgba(34,197,94,.16);color:#22C55E}',
      '#' + MODAL_ID + ' .ic.aviso{background:rgba(245,165,36,.16);color:#F5A524}',
      '#' + MODAL_ID + ' .ic.erro{background:rgba(243,67,107,.16);color:#F3436B}',

      // o texto do erro
      '#' + MODAL_ID + ' .cxerro{background:#191C24;border:1px solid #2B3040;',
      '  border-left:3px solid #F3436B;border-radius:0 8px 8px 0;padding:12px 14px}',
      '#' + MODAL_ID + ' .det.aviso .cxerro{border-left-color:#F5A524}',
      '#' + MODAL_ID + ' .oque{color:#E8EBF0;font-size:13px;line-height:1.5;margin-bottom:9px}',
      '#' + MODAL_ID + ' .cru{color:#8B93A3;font-size:12px;line-height:1.55;',
      '  font-family:Consolas,"Courier New",monospace;word-break:break-word}',
      '#' + MODAL_ID + ' .cru div+div{margin-top:5px}',
      '#' + MODAL_ID + ' .copiar{margin-top:10px;background:#232734;border:1px solid #333949;',
      '  color:#C0C6D1;border-radius:6px;padding:5px 11px;font-size:12px;cursor:pointer;',
      '  font-family:inherit}',
      '#' + MODAL_ID + ' .copiar:hover{background:#2B3040;color:#E8EBF0}',

      '#' + MODAL_ID + ' .mini{color:#F5A524;font-size:12px;font-weight:500;margin-left:4px}',
      '#' + MODAL_ID + ' .vazio{color:#8B93A3;font-size:13px;text-align:center;padding:34px 10px}',
      '#' + MODAL_ID + ' .vazio.err{color:#F3436B}',
      '#' + MODAL_ID + ' .rodape{border-top:1px solid #2B3040;padding:12px 24px;',
      '  color:#8B93A3;font-size:12px}',

      // telas estreitas: a tabela vira blocos, com o rótulo ao lado do valor
      '@media (max-width:640px){',
      '  #' + MODAL_ID + ' .hero .big{font-size:34px}',
      '  #' + MODAL_ID + ' .tb thead{display:none}',
      '  #' + MODAL_ID + ' .tb,#' + MODAL_ID + ' .tb tbody,#' + MODAL_ID + ' .tb tr,',
      '  #' + MODAL_ID + ' .tb td{display:block;width:auto}',
      '  #' + MODAL_ID + ' .tb tr.ln{border-top:1px solid #23272F;padding:10px 0}',
      '  #' + MODAL_ID + ' .tb td{border:none;padding:2px 0;text-align:left!important}',
      '  #' + MODAL_ID + ' .tb td.n::before{content:attr(data-r);color:#8B93A3;',
      '    font-size:11.5px;margin-right:8px;font-weight:500}',
      '}'
    ].join('');
    document.head.appendChild(s);
  }

  function fechar() {
    var m = document.getElementById(MODAL_ID);
    if (m) m.remove();
  }

  function abrir(subtitulo, corpo, rodape) {
    injetarEstilo();
    fechar();

    var m = document.createElement('div');
    m.id = MODAL_ID;
    m.innerHTML =
      '<div class="cx">' +
        '<div class="cab">' +
          '<div><h2>Histórico de backups</h2><div class="sub">' + escapar(subtitulo) + '</div></div>' +
          '<button class="fechar" title="Fechar">&times;</button>' +
        '</div>' +
        '<div class="corpo">' + corpo + '</div>' +
        (rodape ? '<div class="rodape">' + rodape + '</div>' : '') +
      '</div>';

    m.addEventListener('click', function (e) { if (e.target === m) fechar(); });
    m.querySelector('.fechar').addEventListener('click', fechar);
    document.addEventListener('keydown', function esc(e) {
      if (e.key === 'Escape') { fechar(); document.removeEventListener('keydown', esc); }
    });

    document.body.appendChild(m);
  }

  function montar(ex, proxima) {
    if (!ex.length) {
      return '<div class="vazio">Nenhuma execução de backup registrada ainda.</div>';
    }

    // O total guardado vem da execução mais recente que conseguiu medir.
    // Um backup que falha reporta 0, e mostrar esse 0 faria parecer que o
    // backup sumiu da nuvem — quando o que falhou foi a execução de hoje.
    var destino = null, ultimoOk = null;
    for (var i = 0; i < ex.length; i++) {
      if (destino === null && ex[i].noDestino > 0) destino = ex[i].noDestino;
      if (ultimoOk === null && String(ex[i].resultado).toLowerCase() === 'success') ultimoOk = ex[i];
    }

    // Quantas das registradas não terminaram bem — a pergunta que um suporte
    // faz antes de qualquer outra: "isso aqui está confiável?"
    var falhas = 0;
    ex.forEach(function (x) {
      var c = situacao(x.resultado).c;
      if (c === 'erro' || c === 'aviso') falhas++;
    });

    var hero =
      '<div class="hero">' +
        '<div><div class="r">Guardado na nuvem</div>' +
        '<div class="big">' + escapar(bytes(destino)) + '</div></div>' +
        '<div class="lado"><div class="r">Último backup com êxito</div>' +
        '<div class="v">' + escapar(ultimoOk ? quando(ultimoOk.quando) : '—') + '</div></div>' +
        '<div class="lado"><div class="r">Próxima execução</div>' +
        '<div class="v">' + escapar(proxima || '—') + '</div></div>' +
        '<div class="lado"><div class="r">Execuções registradas</div>' +
        '<div class="v">' + ex.length +
          (falhas > 0 ? ' <span class="mini">' + falhas +
                        (falhas === 1 ? ' com problema' : ' com problema') + '</span>' : '') +
        '</div></div>' +
      '</div>';

    // A execução mais antiga registrada é a que criou o backup do zero.
    var idxCompleto = ex.length - 1;

    /* Tabela, não cartões. Antes cada execução repetia os cinco rótulos
       ("Enviado", "Velocidade", "Duração"…): com seis execuções eram trinta
       rótulos na tela dizendo a mesma coisa, e comparar duas execuções
       obrigava a ler dois blocos separados. Numa tabela o rótulo aparece uma
       vez no topo e os números ficam alinhados na mesma coluna — dá para
       correr o olho e ver qual noite foi mais lenta. */
    var linhasTabela = ex.map(function (x, i) {
      var s = situacao(x.resultado);
      var msgs = (x.textoErros || []).concat(x.textoAvisos || []);
      var temDetalhe = msgs.length > 0;

      var principal =
        '<tr class="ln ' + s.c + (temDetalhe ? ' com-det' : '') + '">' +
          '<td class="q" title="' + escapar(quando(x.quando)) + '">' +
            escapar(quandoCurto(x.quando)) +
            (i === idxCompleto ? ' <span class="tag">completo</span>' : '') + '</td>' +
          '<td><span class="est ' + s.c + '">' +
            '<span class="ic ' + s.c + '" aria-hidden="true">' + s.icone + '</span>' +
            escapar(s.texto) + '</span></td>' +
          // data-r repõe o rótulo quando a tela é estreita e o cabeçalho some
          '<td class="n" data-r="Enviado">' + escapar(bytes(x.enviado)) + '</td>' +
          '<td class="n" data-r="Velocidade">' + escapar(velocidade(x.enviado, x.segundos)) + '</td>' +
          '<td class="n" data-r="Duração">' + escapar(duracao(x.segundos)) + '</td>' +
          // Zero aqui não quer dizer "a nuvem está vazia": quando o backup
          // falha antes de listar o destino, o Duplicati reporta 0 porque não
          // conseguiu medir. Mostrar "0 B" faria parecer que o backup sumiu.
          '<td class="n' + (x.noDestino > 0 ? '' : ' fraco') + '" data-r="Na nuvem">' +
            escapar(x.noDestino > 0 ? bytes(x.noDestino) : '—') + '</td>' +
        '</tr>';

      if (!temDetalhe) return principal;

      /* O texto do erro fica À VISTA, não atrás de um clique. Quem abre esta
         tela depois de uma falha veio buscar exatamente isto; esconder num
         "ver detalhes" é devolver o problema para a pessoa. */
      var explicacao = explicar(msgs);
      var det =
        '<tr class="det ' + s.c + '"><td colspan="6"><div class="cxerro">' +
          (explicacao ? '<div class="oque">' + escapar(explicacao) + '</div>' : '') +
          '<div class="cru">' + msgs.map(function (t) {
              return '<div>' + escapar(t) + '</div>';
            }).join('') + '</div>' +
          '<button class="copiar" type="button" data-txt="' +
            escapar(quando(x.quando) + '\n' + msgs.join('\n')) +
            '">Copiar mensagem</button>' +
        '</div></td></tr>';

      return principal + det;
    }).join('');

    var tabela =
      '<div class="lt">Cada execução, da mais recente para a mais antiga</div>' +
      '<div class="rolo"><table class="tb"><thead><tr>' +
        '<th>Quando</th><th>Situação</th>' +
        '<th class="n">Enviado</th><th class="n">Velocidade</th>' +
        '<th class="n">Duração</th><th class="n">Na nuvem</th>' +
      '</tr></thead><tbody>' + linhasTabela + '</tbody></table></div>';

    return hero + grafico(ex) + tabela;
  }

  /* Copiar a mensagem: quem vê a falha quase sempre precisa mandar o texto
     para outra pessoa. Digitar à mão um erro em inglês de três linhas é
     onde nascem os relatos errados. */
  function ligarCopiar() {
    var m = document.getElementById(MODAL_ID);
    if (!m) return;
    Array.prototype.forEach.call(m.querySelectorAll('.copiar'), function (b) {
      b.addEventListener('click', function () {
        var txt = b.getAttribute('data-txt') || '';
        var pronto = function () {
          b.textContent = 'Copiado';
          setTimeout(function () { b.textContent = 'Copiar mensagem'; }, 1800);
        };
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(txt).then(pronto, function () { selecionar(b); });
        } else {
          selecionar(b);
        }
      });
    });
  }

  // Sem área de transferência (http sem TLS bloqueia em alguns navegadores):
  // seleciona o texto para a pessoa dar Ctrl+C.
  function selecionar(botao) {
    var cx = botao.parentElement && botao.parentElement.querySelector('.cru');
    if (!cx || !window.getSelection) return;
    var faixa = document.createRange();
    faixa.selectNodeContents(cx);
    var sel = window.getSelection();
    sel.removeAllRanges();
    sel.addRange(faixa);
    botao.textContent = 'Selecionado — use Ctrl+C';
  }

  function mostrar(nomeVisivel) {
    abrir(nomeVisivel || '', '<div class="vazio">Consultando o histórico…</div>', null);

    acharBackup(nomeVisivel)
      .then(function (item) {
        var b = item && (item.Backup || item);
        if (!b || !b.ID) throw new Error('não identifiquei de qual backup é este cartão');
        return api('/api/v1/backup/' + b.ID + '/log?pagesize=200').then(function (log) {
          return { nome: b.Name, ex: execucoesDeBackup(log), proxima: proximaExecucao(item) };
        });
      })
      .then(function (r) {
        abrir(r.nome, montar(r.ex, r.proxima),
          '<b>Enviado</b> é o que subiu naquela execução &middot; ' +
          '<b>Na nuvem</b> é o total guardado depois dela');
        ligarCopiar();
      })
      .catch(function (e) {
        abrir(nomeVisivel || '',
          '<div class="vazio err">Não consegui obter o histórico.<br><br>' +
          escapar(e.message) + '</div>',
          'Se a sessão tiver expirado, atualize a página e tente de novo.');
      });
  }

  // --- torna o rótulo clicável --------------------------------------------

  var PADRAO = /^\s*(\d+\s+vers(ion|ions|ão|ões)|no\s+versions?|nenhuma\s+versão)\s*$/i;

  function ehRotulo(el) {
    if (!el || !el.textContent) return false;
    if (el.children.length > 0) return false;
    return PADRAO.test(el.textContent);
  }

  function nomeDoCartao(el) {
    var no = el;
    for (var i = 0; i < 8 && no; i++) {
      no = no.parentElement;
      if (!no) break;
      var t = (no.innerText || '').trim();
      if (t.length > 40) {
        var primeira = t.split('\n')[0].trim();
        if (primeira && !PADRAO.test(primeira)) return primeira;
      }
    }
    return null;
  }

  function marcar() {
    var todos = document.querySelectorAll('span,div,p,small,strong,b,em');
    for (var i = 0; i < todos.length; i++) {
      var el = todos[i];
      if (el.dataset && el.dataset.chcomVersoes) continue;
      if (!ehRotulo(el)) continue;

      el.dataset.chcomVersoes = '1';
      el.classList.add('chcom-versoes-botao');
      el.title = 'Clique para ver o histórico de backups';

      (function (alvo) {
        alvo.addEventListener('click', function (ev) {
          ev.preventDefault();
          ev.stopPropagation();
          mostrar(nomeDoCartao(alvo));
        });
      })(el);
    }
  }

  function iniciar() {
    espiarToken();   // antes de tudo: quanto antes escutar, mais cedo há token
    injetarEstilo();
    marcar();
    if (window.MutationObserver) {
      var t = null;
      new MutationObserver(function () {
        clearTimeout(t);
        t = setTimeout(marcar, 150);
      }).observe(document.documentElement, { childList: true, subtree: true });
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', iniciar);
  } else {
    iniciar();
  }
})();
