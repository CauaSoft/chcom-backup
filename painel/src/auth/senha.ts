import crypto from 'node:crypto';

/**
 * Guarda e confere senhas.
 *
 * Usa scrypt, que vem embutido no Node — sem dependência externa, sem módulo
 * nativo para compilar. scrypt é uma função de derivação DELIBERADAMENTE
 * lenta e que exige muita memória, o que é exatamente o que se quer aqui:
 * torna caro para um atacante testar bilhões de senhas caso o banco vaze.
 *
 * Um hash comum como SHA-256 seria um erro grave nesse papel — ele é rápido
 * de propósito, e uma placa de vídeo testa bilhões de SHA-256 por segundo.
 */

// Fator de custo. 2^16 = 65536 leva algumas centenas de milissegundos numa
// máquina comum, o que é imperceptível num login e proibitivo em massa.
const CUSTO_N = 65536;
const TAMANHO_CHAVE = 64;

// O scrypt do Node tem um limite de memória padrão que o custo acima
// ultrapassa; sem elevar isso, a chamada falha com "memory limit exceeded".
const OPCOES: crypto.ScryptOptions = { N: CUSTO_N, r: 8, p: 1, maxmem: 128 * CUSTO_N * 8 * 2 };

export interface SenhaGuardada {
  hash: string;
  sal: string;
}

export function gerarHash(senha: string): SenhaGuardada {
  const sal = crypto.randomBytes(16).toString('hex');
  const hash = crypto.scryptSync(senha, sal, TAMANHO_CHAVE, OPCOES).toString('hex');
  return { hash, sal };
}

/**
 * Confere a senha.
 *
 * A comparação usa `timingSafeEqual`, que leva o mesmo tempo independente de
 * onde os bytes começam a divergir. Um `===` comum retorna mais rápido quando
 * a diferença está no primeiro caractere, e essa diferença de tempo — mesmo
 * de microssegundos — pode ser medida e usada para descobrir o hash byte a
 * byte.
 */
export function conferir(senha: string, guardada: SenhaGuardada): boolean {
  let calculado: Buffer;
  try {
    calculado = crypto.scryptSync(senha, guardada.sal, TAMANHO_CHAVE, OPCOES);
  } catch {
    return false;
  }

  const esperado = Buffer.from(guardada.hash, 'hex');
  if (esperado.length !== calculado.length) return false;

  return crypto.timingSafeEqual(esperado, calculado);
}

/**
 * Gera uma senha aleatória legível, para a primeira configuração.
 *
 * Sem caracteres que se confundem ao ler em voz alta ou anotar no papel:
 * nada de O e 0, l e 1, I. Uma senha que o técnico digita errado três vezes
 * acaba virando "123456" no dia seguinte.
 */
export function gerarSenhaAleatoria(tamanho = 20): string {
  const alfabeto = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';
  const bytes = crypto.randomBytes(tamanho);
  let saida = '';
  for (let i = 0; i < tamanho; i++) {
    // O módulo enviesa levemente a distribuição, mas com 56 símbolos e 20
    // caracteres a entropia continua acima de 110 bits — folgada demais para
    // o viés importar aqui.
    saida += alfabeto[bytes[i]! % alfabeto.length];
  }
  return saida;
}
