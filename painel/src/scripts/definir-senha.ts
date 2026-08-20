import { aplicarSchema } from '../db';
import { contarAdmins, definirAdmin } from '../db/repo';
import { gerarHash, gerarSenhaAleatoria } from '../auth/senha';

/**
 * Cria o administrador do painel, ou troca a senha dele.
 *
 *   npm run definir-senha
 *       gera uma senha forte e mostra UMA vez. É o jeito recomendado.
 *
 *   npm run definir-senha -- --usuario admin --senha "sua-senha-aqui"
 *       define uma senha escolhida por você.
 *
 * Trocar a senha encerra todas as sessões abertas. Se a troca aconteceu
 * porque a senha vazou, deixar as sessões vivas anularia o motivo da troca.
 */

function argumento(nome: string): string | undefined {
  const i = process.argv.indexOf(`--${nome}`);
  if (i === -1) return undefined;
  return process.argv[i + 1];
}

aplicarSchema();

const usuario = (argumento('usuario') ?? 'admin').trim();
const senhaInformada = argumento('senha');

if (!usuario) {
  console.error('O nome de usuário não pode ser vazio.');
  process.exit(1);
}

// Um mínimo que barra o "1234" sem virar uma lista de regras que só leva a
// senha anotada num papel colado no monitor.
if (senhaInformada !== undefined && senhaInformada.length < 10) {
  console.error('');
  console.error('  A senha precisa ter pelo menos 10 caracteres.');
  console.error('  Ou rode sem --senha para o painel gerar uma senha forte.');
  console.error('');
  process.exit(1);
}

const gerada = senhaInformada === undefined;
const senha = senhaInformada ?? gerarSenhaAleatoria();

const jaExistia = contarAdmins() > 0;
const { hash, sal } = gerarHash(senha);
definirAdmin(usuario, hash, sal);

console.log('');
console.log(jaExistia ? '  Senha alterada.' : '  Administrador criado.');
console.log('');
console.log(`  usuário  ${usuario}`);

if (gerada) {
  console.log(`  senha    ${senha}`);
  console.log('');
  console.log('  ANOTE ESTA SENHA AGORA. Ela não é guardada em lugar nenhum —');
  console.log('  o banco só tem o hash, e não há como recuperá-la depois.');
  console.log('  Se perder, rode este comando de novo para gerar outra.');
} else {
  console.log('  senha    (a que você informou)');
  console.log('');
  console.log('  Atenção: a senha passada por linha de comando fica no');
  console.log('  histórico do terminal. Para limpar no PowerShell, apague');
  console.log('  o arquivo em (Get-PSReadlineOption).HistorySavePath');
}

if (jaExistia) {
  console.log('');
  console.log('  As sessões abertas foram encerradas. Todos precisam entrar de novo.');
}

console.log('');
