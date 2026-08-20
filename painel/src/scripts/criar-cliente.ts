import { aplicarSchema } from '../db';
import { criarCliente } from '../db/repo';
import { config } from '../config';

/**
 * Cadastra um cartório e mostra a URL pronta para colar no Duplicati.
 *
 *   npm run criar-cliente -- "1º Ofício de Porto Velho" "Porto Velho"
 *
 * (o `--` é necessário: sem ele o npm engole os argumentos)
 */

const [, , nome, cidade] = process.argv;

if (!nome || !cidade) {
  console.error('');
  console.error('  Uso:');
  console.error('    npm run criar-cliente -- "<nome do cartório>" "<cidade>"');
  console.error('');
  console.error('  Exemplo:');
  console.error(
    '    npm run criar-cliente -- "1º Ofício de Porto Velho" "Porto Velho"',
  );
  console.error('');
  process.exit(1);
}

aplicarSchema();

const cliente = criarCliente(nome, cidade);
const url = `http://localhost:${config.porta}/api/report/${cliente.token}`;

console.log('');
console.log('  Cartório cadastrado');
console.log('');
console.log(`  id      ${cliente.id}`);
console.log(`  nome    ${cliente.nome}`);
console.log(`  cidade  ${cliente.cidade}`);
console.log(`  token   ${cliente.token}`);
console.log('');
console.log('  URL para o Duplicati deste cartório:');
console.log('');
console.log(`    ${url}`);
console.log('');
console.log('  No Duplicati do cartório, vá em Configurações -> Opções');
console.log('  avançadas e adicione:');
console.log('');
console.log(`    send-http-json-urls = ${url}`);
console.log('');
console.log('  Em produção troque localhost pelo endereço público do painel.');
console.log('');
