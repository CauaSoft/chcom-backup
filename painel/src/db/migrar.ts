import { aplicarSchema, db } from './index';
import { config } from '../config';

/**
 * Cria as tabelas. Pode rodar quantas vezes quiser — o schema é idempotente.
 *
 *   npm run migrar
 */

aplicarSchema();

const tabelas = db()
  .prepare(
    `SELECT name FROM sqlite_master
      WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
      ORDER BY name`,
  )
  .all() as Array<{ name: string }>;

console.log(`banco: ${config.bancoCaminho}`);
console.log('tabelas:');
for (const t of tabelas) {
  const { n } = db().prepare(`SELECT COUNT(*) AS n FROM "${t.name}"`).get() as {
    n: number;
  };
  console.log(`  ${t.name.padEnd(24)} ${n} registro(s)`);
}
