# Gera o branding/oem-custom.js, que leva o nome e o logo da CH.Com para a
# interface NOVA do Duplicati (ngclient).
#
# Uso:  powershell -ExecutionPolicy Bypass -File branding\gerar-oem-js.ps1
#
# ---------------------------------------------------------------------------
# POR QUE ISTO FUNCIONA SEM RECOMPILAR O NGCLIENT
#
# A interface nova vem compilada do npm e o fonte não está no repositório,
# então por muito tempo pareceu que nome e logo dela eram intocáveis. Não são:
# o componente app-logo do ngclient lê, ao iniciar,
#
#     window.BRANDING_LOGO   -> endereço da imagem do logo
#     window.BRANDING_NAME   -> texto ao lado do logo
#
# Se BRANDING_LOGO estiver definido, ele troca o SVG do Duplicati pela nossa
# imagem; se BRANDING_NAME estiver definido, troca o texto "duplicati".
#
# E o servidor injeta oem-custom.js no <head> de toda interface servida como
# SPA. Ou seja: basta o arquivo existir na pasta do executável.
#
# O logo vai embutido como data URI em vez de um caminho de arquivo. Um
# caminho quebraria quando o painel estivesse atrás de um proxy com prefixo
# (o /ngclient/ deixa de ser a raiz), e o data URI não depende de caminho
# nenhum.
# ---------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'

$dir = Join-Path $PSScriptRoot 'logo'
$origem = Join-Path $dir 'logo-64.png'

if (-not (Test-Path $origem)) {
    Write-Error "Nao encontrei $origem. Rode gerar-logos.ps1 ou redimensionar-logo.ps1 antes."
    exit 1
}

$bytes = [System.IO.File]::ReadAllBytes($origem)
$base64 = [System.Convert]::ToBase64String($bytes)

$conteudo = @"
/* ==========================================================================
   CH.Com Backup - nome e logo da interface nova (ngclient)
   Projeto: Painel Backup CH.Com (fork de rebrand do Duplicati)

   Baseado em Duplicati, MIT License, Copyright (c) 2026 Duplicati Inc.

   ARQUIVO GERADO. Nao edite a mao: rode branding\gerar-oem-js.ps1.

   O componente app-logo do ngclient le estas duas variaveis quando inicia.
   Definidas aqui, ele troca o logo e o nome sem precisar recompilar nada.
   O servidor injeta este arquivo sozinho, desde que ele esteja na pasta do
   executavel com o nome exato oem-custom.js.
   ========================================================================== */

window.BRANDING_NAME = 'CH.Com Backup';
window.BRANDING_LOGO = 'data:image/png;base64,$base64';

/* --------------------------------------------------------------------------
   Tema escuro por padrao

   A identidade da CH.Com e clara sobre fundo escuro (#14161C). No tema claro
   aparece o azul e o logo, mas nao a cara do produto -- e a primeira
   impressao de quem abre no cartorio e "um Duplicati meio azul".

   O ngclient guarda a escolha de tema em localStorage. Aqui so definimos o
   escuro quando NAO ha escolha gravada: se o usuario trocar para claro
   depois, a escolha dele e respeitada e nao voltamos a mexer.

   A classe e aplicada no <html> na hora, alem de gravar a preferencia,
   porque o ngclient le o localStorage antes de nos e ja teria pintado claro.
   -------------------------------------------------------------------------- */
(function () {
  var CHAVE = 'v1:persist:duplicati:darkTheme';

  try {
    if (localStorage.getItem(CHAVE) === null) {
      localStorage.setItem(CHAVE, 'true');
    }

    if (localStorage.getItem(CHAVE) === 'true') {
      var raiz = document.documentElement;
      raiz.classList.remove('light');
      raiz.classList.add('dark');
    }
  } catch (e) {
    /* localStorage bloqueado: segue no tema padrao, sem quebrar a pagina */
  }
})();

/* --------------------------------------------------------------------------
   Troca a palavra "Duplicati" em todo texto visivel da interface

   O BRANDING_NAME cobre o cabecalho, mas sobram varios lugares escritos fixos
   dentro do bundle compilado: "About Duplicati" no menu lateral, mensagens de
   erro, textos de ajuda, rotulos de dialogo. Nenhum deles e configuravel, e
   nao ha como edita-los sem o repositorio-fonte do ngclient.

   Entao trocamos no proprio navegador, no texto ja renderizado.

   Cuidados que este codigo toma:

   - Mexe SO em nos de texto. Nao toca em atributos, em valor de campo de
     formulario, nem em nada dentro de <script> ou <style> -- trocar texto
     dentro de um script quebraria a aplicacao.
   - Nao entra em <input>/<textarea>: se o usuario digitar "Duplicati" num
     campo, o que ele digitou fica como esta.
   - Nao entra em laco: depois da troca o texto nao contem mais "Duplicati",
     entao a proxima notificacao do observer nao encontra nada para alterar.
   -------------------------------------------------------------------------- */
(function () {
  var NOME = 'CH.Com Backup';
  var PROIBIDOS = { SCRIPT: 1, STYLE: 1, INPUT: 1, TEXTAREA: 1, CODE: 1, PRE: 1 };

  function trocar(raiz) {
    if (!raiz || !raiz.querySelectorAll) return;

    var caminhador = document.createTreeWalker(raiz, NodeFilter.SHOW_TEXT, {
      acceptNode: function (no) {
        if (!no.nodeValue || no.nodeValue.indexOf('Duplicati') === -1) {
          return NodeFilter.FILTER_REJECT;
        }
        var pai = no.parentNode;
        if (pai && PROIBIDOS[pai.nodeName]) return NodeFilter.FILTER_REJECT;
        return NodeFilter.FILTER_ACCEPT;
      }
    });

    var achados = [];
    var no;
    while ((no = caminhador.nextNode())) achados.push(no);

    for (var i = 0; i < achados.length; i++) {
      achados[i].nodeValue = achados[i].nodeValue
        .replace(/About Duplicati/g, 'Sobre o ' + NOME)
        .replace(/Duplicati/g, NOME);
    }
  }

  function agora() { try { trocar(document.body); } catch (e) { } }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', agora);
  } else {
    agora();
  }

  /* A interface e um aplicativo de pagina unica: o conteudo aparece depois,
     e muda a cada navegacao. Sem observar, so a primeira tela seria tratada. */
  if (window.MutationObserver) {
    new MutationObserver(function (alteracoes) {
      for (var i = 0; i < alteracoes.length; i++) {
        var a = alteracoes[i];
        for (var j = 0; j < a.addedNodes.length; j++) {
          var n = a.addedNodes[j];
          if (n.nodeType === 1) trocar(n);
          else if (n.nodeType === 3 && n.nodeValue && n.nodeValue.indexOf('Duplicati') !== -1) {
            var pai = n.parentNode;
            if (!pai || !PROIBIDOS[pai.nodeName]) {
              n.nodeValue = n.nodeValue
                .replace(/About Duplicati/g, 'Sobre o ' + NOME)
                .replace(/Duplicati/g, NOME);
            }
          }
        }
      }
    }).observe(document.documentElement, { childList: true, subtree: true });
  }
})();

/* --------------------------------------------------------------------------
   Titulo da aba

   O ngclient nasce com <title>Duplicati ngclient</title> e reescreve o titulo
   ao navegar entre telas, entao trocar uma vez no carregamento nao basta: o
   "Duplicati" volta na primeira navegacao. Um MutationObserver no <title>
   corrige toda vez que ele muda.

   A troca so acontece quando o titulo contem "Duplicati", e por isso o
   observer nao entra em laco: depois de corrigido, o texto nao casa mais e a
   proxima notificacao nao dispara alteracao nenhuma.
   -------------------------------------------------------------------------- */
(function () {
  var NOME = 'CH.Com Backup';

  function ajustar() {
    var t = document.title || '';
    if (t.indexOf('Duplicati') === -1) return;
    document.title = t.replace(/Duplicati(\s+ngclient)?/g, NOME);
  }

  ajustar();

  var alvo = document.querySelector('title');
  if (alvo && window.MutationObserver) {
    new MutationObserver(ajustar).observe(alvo, {
      childList: true,
      characterData: true,
      subtree: true
    });
  }
})();
"@

# A tela de versões é grande e vive em arquivo próprio, para poder ser lida e
# editada como código normal. Aqui ela é anexada ao oem-custom.js, porque o
# servidor injeta um arquivo só.
$telaVersoes = Join-Path $PSScriptRoot 'versoes.js'
if (Test-Path $telaVersoes) {
    # ReadAllText com UTF8 explicito, NUNCA Get-Content. No Windows PowerShell
    # 5.1 o Get-Content le usando a pagina de codigo ANSI do Windows, entao um
    # arquivo UTF-8 sem BOM chega corrompido: o "o" acentuado (bytes 195 179)
    # vira dois caracteres, e ao gravar de volta em UTF-8 sai 195 131 194 179.
    # E assim que "Historico" virava "HistA3rico" na tela do cartorio - o erro
    # acontecia aqui, na geracao, nao na entrega.
    $conteudo = $conteudo + "`r`n`r`n" +
        [System.IO.File]::ReadAllText($telaVersoes, [System.Text.UTF8Encoding]::new($false))
} else {
    Write-Warning "versoes.js nao encontrado; o oem-custom.js sai sem a tela de versoes."
}

$destino = Join-Path $PSScriptRoot 'oem-custom.js'

# Com BOM. O Duplicati serve este arquivo como "application/javascript" SEM
# charset; sem charset o navegador so acerta a leitura porque a pagina que o
# carrega declara UTF-8. O BOM tira essa dependencia - tem precedencia sobre
# o Content-Type na especificacao do HTML e vale mesmo se a pagina mudar.
[System.IO.File]::WriteAllText($destino, $conteudo, [System.Text.UTF8Encoding]::new($true))

$kb = [math]::Round((Get-Item $destino).Length / 1KB, 1)
Write-Host "gerado: $destino ($kb KB, logo embutido como data URI)"
