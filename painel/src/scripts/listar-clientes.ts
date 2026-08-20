import { aplicarSchema } from '../db';
import { listarClientes } from '../db/repo';
import { config } from '../config';

/**
 * Lista os cartórios cadastrados com a URL de cada um.
 *
 *   npm run listar-clientes
 */

aplicarSchema();

const clientes = listarClientes();

if (clientes.length === 0) {
  console.log('');
  console.log('  Nenhum cartório cadastrado ainda.');
  console.log('');
  console.log('  Cadastre o primeiro com:');
  console.log('    npm run criar-cliente -- "Nome do Cartório" "Cidade"');
  console.log('');
  process.exit(0);
}

console.log('');
console.log(`  ${clientes.length} cartório(s) cadastrado(s):`);
console.log('');

for (const c of clientes) {
  const situacao = c.ativo ? '' : '  [DESATIVADO]';
  console.log(`  #${c.id}  ${c.nome} — ${c.cidade}${situacao}`);
  console.log(
    `      http://localhost:${config.porta}/api/report/${c.token}`,
  );
  console.log('');
}
