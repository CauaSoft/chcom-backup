import { aplicarSchema, db } from '../db';
import { criarCliente, salvarRelatorio } from '../db/repo';
import { extrairCampos, VERSAO_PARSER } from '../duplicati/parse';

/**
 * Gera cartórios e histórico FALSOS para ver o painel funcionando antes de
 * ligar num Duplicati de verdade.
 *
 *   npm run dados-demo
 *
 * Os dados são inventados, mas passam pelo MESMO caminho de um relatório
 * real: o script monta o JSON no formato do Duplicati e ele é lido pelo
 * parser de produção. Se o parser quebrar, o gerador quebra junto — o que
 * é justamente o que queremos de um dado de teste.
 *
 * Para limpar tudo depois:
 *   npm run dados-demo -- --limpar
 */

const limpar = process.argv.includes('--limpar');

aplicarSchema();

if (limpar) {
  // A ordem importa: relatorios referencia clientes por chave estrangeira,
  // e apagar o cliente primeiro seria recusado pelo banco.
  db().exec('DELETE FROM relatorios; DELETE FROM recebimentos_recusados; DELETE FROM clientes;');
  console.log('');
  console.log('  Banco limpo. Nenhum cartório, nenhum relatório.');
  console.log('');
  process.exit(0);
}

/**
 * Gera um relatório no formato do Duplicati.
 *
 * `Math.random()` é adequado aqui: são dados de vitrine, não tokens. Onde
 * a aleatoriedade precisa ser imprevisível — na geração de token — usamos
 * crypto, em src/db/repo.ts.
 */
function montarRelatorio(opcoes: {
  fim: Date;
  duracaoSegundos: number;
  tamanhoOrigem: number;
  tamanhoAdicionado: number;
  bytesEnviados: number;
  tamanhoDestino: number;
  resultado: 'Success' | 'Warning' | 'Error';
  avisos: number;
  erros: number;
}) {
  const inicio = new Date(opcoes.fim.getTime() - opcoes.duracaoSegundos * 1000);

  const h = Math.floor(opcoes.duracaoSegundos / 3600);
  const m = Math.floor((opcoes.duracaoSegundos % 3600) / 60);
  const s = opcoes.duracaoSegundos % 60;
  const duracao = `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}.0000000`;

  return {
    Data: {
      ExaminedFiles: 45000 + Math.floor(Math.random() * 3000),
      AddedFiles: Math.floor(Math.random() * 40),
      ModifiedFiles: Math.floor(Math.random() * 60),
      DeletedFiles: 0,
      SizeOfExaminedFiles: opcoes.tamanhoOrigem,
      SizeOfAddedFiles: opcoes.tamanhoAdicionado,
      SizeOfModifiedFiles: Math.floor(opcoes.tamanhoAdicionado * 0.4),
      PartialBackup: false,
      Dryrun: false,
      MainOperation: 'Backup',
      ParsedResult: opcoes.resultado,
      Interrupted: false,
      Version: '2.3.0.4 (2.3.0.4_stable_2026-07-09)',
      BeginTime: inicio.toISOString(),
      EndTime: opcoes.fim.toISOString(),
      Duration: duracao,
      MessagesActualLength: 40 + Math.floor(Math.random() * 20),
      WarningsActualLength: opcoes.avisos,
      ErrorsActualLength: opcoes.erros,
      BackendStatistics: {
        RemoteCalls: 8 + Math.floor(Math.random() * 12),
        BytesUploaded: opcoes.bytesEnviados,
        BytesDownloaded: 0,
        FilesUploaded: 1 + Math.floor(Math.random() * 4),
        KnownFileCount: 1200 + Math.floor(Math.random() * 200),
        KnownFileSize: opcoes.tamanhoDestino,
        BackupListCount: 30 + Math.floor(Math.random() * 20),
        MainOperation: 'Backup',
        ParsedResult: opcoes.resultado,
      },
    },
    Extra: {
      OperationName: 'Backup',
      'machine-name': 'SRV-CARTORIO',
      'backup-name': 'Backup Sistema Cartorio',
    },
    LogLines: [],
  };
}

interface Perfil {
  nome: string;
  cidade: string;
  dias: number;
  origemInicialGB: number;
  destinoInicialGB: number;
  /** Como termina o backup MAIS RECENTE. Os anteriores são quase todos OK. */
  final: 'Success' | 'Warning' | 'Error';
  /** Dias sem reportar no fim, para simular um cartório atrasado. */
  atrasoDias?: number;
}

const PERFIS: Perfil[] = [
  {
    nome: '1º Ofício de Registro Civil de Porto Velho',
    cidade: 'Porto Velho',
    dias: 45,
    origemInicialGB: 174,
    destinoInicialGB: 198,
    final: 'Success',
  },
  {
    nome: '2º Tabelionato de Notas de Ji-Paraná',
    cidade: 'Ji-Paraná',
    dias: 30,
    origemInicialGB: 62,
    destinoInicialGB: 71,
    final: 'Warning',
  },
  {
    nome: 'Cartório de Registro de Imóveis de Ariquemes',
    cidade: 'Ariquemes',
    dias: 22,
    origemInicialGB: 310,
    destinoInicialGB: 345,
    final: 'Error',
  },
  {
    nome: 'Tabelionato de Protesto de Vilhena',
    cidade: 'Vilhena',
    dias: 18,
    origemInicialGB: 41,
    destinoInicialGB: 47,
    final: 'Success',
    atrasoDias: 6,
  },
];

const GB = 1024 * 1024 * 1024;
const agora = Date.now();

console.log('');
console.log('  Gerando dados de demonstração...');
console.log('');

for (const perfil of PERFIS) {
  const cliente = criarCliente(perfil.nome, perfil.cidade);

  let origem = perfil.origemInicialGB * GB;
  let destino = perfil.destinoInicialGB * GB;

  for (let i = perfil.dias; i >= 1; i--) {
    const diasAtras = i - 1 + (perfil.atrasoDias ?? 0);

    // Backup às 03:00 de cada dia
    const fim = new Date(agora - diasAtras * 86400_000);
    fim.setHours(3, 0, 0, 0);
    const duracaoSegundos = 180 + Math.floor(Math.random() * 500);

    // A origem cresce de 0,05% a 0,35% por dia; o destino acompanha, mas com
    // menos, por causa da compressão e da deduplicação do Duplicati.
    const crescimento = 0.0005 + Math.random() * 0.003;
    const adicionado = Math.floor(origem * crescimento);
    const enviado = Math.floor(adicionado * (0.25 + Math.random() * 0.35));

    origem += adicionado;
    destino += enviado;

    const ultimo = i === 1;
    const resultado = ultimo ? perfil.final : Math.random() < 0.12 ? 'Warning' : 'Success';
    const avisos = resultado === 'Warning' ? 1 + Math.floor(Math.random() * 5) : 0;
    const erros = resultado === 'Error' ? 1 + Math.floor(Math.random() * 3) : 0;

    const relatorio = montarRelatorio({
      fim,
      duracaoSegundos,
      tamanhoOrigem: Math.floor(origem),
      tamanhoAdicionado: adicionado,
      bytesEnviados: enviado,
      tamanhoDestino: Math.floor(destino),
      resultado,
      avisos,
      erros,
    });

    const bruto = JSON.stringify(relatorio);
    const { campos } = extrairCampos(JSON.parse(bruto));
    salvarRelatorio(cliente.id, campos, bruto, VERSAO_PARSER, fim.toISOString());
  }

  const nota = perfil.atrasoDias ? `  (sem reportar há ${perfil.atrasoDias} dias)` : '';
  console.log(
    `  #${cliente.id}  ${perfil.nome} — ${perfil.dias} backups, termina em ${perfil.final}${nota}`,
  );
}

// Um cartório recém-cadastrado, que ainda não reportou nada. É o estado que
// mais aparece durante o onboarding dos 38 cartórios, e o painel precisa
// mostrá-lo claramente em vez de escondê-lo.
const novo = criarCliente('Cartório de Registro Civil de Cacoal', 'Cacoal');
console.log(`  #${novo.id}  ${novo.nome} — nunca reportou (recém-cadastrado)`);

console.log('');
console.log('  Pronto. Abra http://localhost:3000');
console.log('');
console.log('  Estes dados são FALSOS. Para apagar tudo:');
console.log('    npm run dados-demo -- --limpar');
console.log('');
