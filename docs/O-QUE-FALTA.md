# O que está provado, o que não está

Atualizado em 31/08/2026. Serve para uma coisa só: separar o que foi
**exercitado de verdade** do que só existe como código.

Quem lê isso está decidindo se pode prometer proteção a um cartório. A regra
aqui é: só entra na coluna "provado" o que rodou e foi conferido.

---

## Provado — rodou e foi conferido

| O quê | Como foi provado |
|---|---|
| Exportar VM do Hyper-V ligada | 13,11 GB em 7min47, production checkpoint, sem parar o serviço |
| Validar que a VM exportada importa | `Compare-VM -Copy -GenerateNewId` num destino limpo |
| Copiar pasta com arquivo aberto | cópia de sombra (VSS) + robocopy, códigos 0–7 tratados como sucesso |
| Impressão digital SHA-256 | manifesto gerado e conferido, ida e volta |
| **Enviar para a AWS** | **8 MB subiram, foram conferidos, velocidade medida** |
| Ler o parque do bucket | 5 servidores em 0,4 s, sem a chave de nenhum cartório |
| Interface | 5 cenários × 9 telas, todo botão clicado, sem quebra e sem travar |
| Instalador `.exe` | gerado pelo iexpress, dois cliques, sem ferramenta externa |
| O programa se configurar sozinho | sem configuração, a janela abriu e o assistente subiu junto |

---

## Codificado, nunca exercitado

Isto é o que impede de dizer que um cartório está protegido.

| O quê | Por que não foi provado |
|---|---|
| **Restaurar do Deep Archive** | precisa de backup real lá dentro e de 12 a 48 h de espera |
| **Descongelar** (`backend restore`) | idem — e é o passo que ninguém testa até precisar |
| **A tarefa agendada disparando** | registrar exige administrador; o código foi conferido, o disparo não |
| `Import-VM` no destino | nunca houve um export restaurado em outra máquina |
| `wbadmin start backup` | só existe em Windows Server; a VM de teste é Windows 10 |
| `gbak` no Firebird | não há Firebird em nenhuma máquina de teste |
| `BACKUP DATABASE` no SQL Server | idem |
| Uma noite completa sem ninguém | nunca aconteceu |

**A restauração é a única coisa que importa de verdade num backup.** Todo o
resto é preparação para ela.

---

## Sobre o agendamento — o que mudou hoje

Dois defeitos que explicavam "não tem nada concreto":

**As duas tarefas rodavam o mesmo comando.** `cofre.ps1` sem argumento, nas
duas. A diária — descrita como "cópia dos bancos" — fazia a rodada completa:
VMs e imagem, toda madrugada. Numa VM de 21 GB por 10 Mbps são 2,3 h por noite
em vez de por mês, e 30 cópias completas por mês em Deep Archive.

**O erro era engolido por um `catch { }` vazio.** Sem permissão, com política
de domínio, com o serviço do Agendador parado: nada ficava agendado e o
assistente dizia "configuração concluída".

Agora a diária passa `-SomenteBancos`, a mensal passa `-Tudo`, o registro é
conferido no Agendador depois de feito, e a tela final diz em vermelho quando
não conseguiu.

**O que continua sem prova:** que a tarefa realmente dispara à 01:30 com o
programa fechado. O registro exige administrador e não foi feito.

---

## O que fazer, em ordem

### 1. A AWS
`aws/COMECAR-NA-AWS.md`. Bucket com versionamento e Object Lock em modo
Governança, e um usuário IAM por cartório. 20 minutos, uma vez.

### 2. Um backup real, pequeno
Uma pasta de poucos MB, pelo `Executar agora`. Depois, `O que é protegido` →
**Conferir na nuvem**. Isso fecha o ciclo de ida.

### 3. Uma noite
Deixar a máquina ligada e conferir de manhã se a tarefa das 01:30 rodou. É a
única forma de provar que funciona com o programa fechado.

### 4. A restauração completa

```
restaurar-cofre.ps1 -Listar
restaurar-cofre.ps1 -Descongelar "<caminho>"        (espera até 48 h)
restaurar-cofre.ps1 -Situacao "<caminho>"
restaurar-cofre.ps1 -Baixar "<caminho>" -Para "D:\teste"
```

Enquanto isso não acontecer uma vez, **não sabemos se o Cofre restaura**.

### 5. Um servidor de verdade
Windows Server com Hyper-V e Firebird. É onde `wbadmin` e `gbak` deixam de ser
teoria.

---

## Decisões que valem revisar

**Cada backup é uma cópia inteira.** O destino é `<DISCO>/<AAAA-MM-DD>/`, e
nada é reaproveitado entre datas. Dá pontos de recuperação independentes e
custa upload cheio toda vez. Numa VM de 21 GB por mês, tudo bem. Numa pasta de
500 GB, não.

**O ciclo de vida do bucket ainda não existe.** Nada apaga cópia velha hoje.
Sem uma regra de expiração, o custo cresce para sempre.

**O estado vai sem cifra.** Só o `_estado/estado.json` — o backup continua
cifrado com a chave de cada cartório. Sem isso o modo gerente não funcionaria,
porque a chave do gerente não decifra cartório nenhum. Fica visível no bucket:
nome do cartório, do servidor, dos itens, datas e tamanhos.
