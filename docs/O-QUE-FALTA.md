# O que está provado, o que não está

Escrito em 31/08/2026. Serve para uma coisa só: separar o que já foi
**exercitado de verdade** do que só existe como código.

Quem lê isso está decidindo se pode prometer proteção a um cartório. Então a
regra aqui é: só entra na coluna "provado" o que rodou e foi conferido.

---

## Provado — rodou de verdade e foi conferido

| O quê | Como foi provado |
|---|---|
| Exportar VM do Hyper-V ligada | 13,11 GB em 7min47, com production checkpoint, sem parar o serviço |
| Validar que a VM exportada importa | `Compare-VM -Copy -GenerateNewId` num destino limpo |
| Copiar pasta com arquivo aberto | cópia de sombra (VSS) + robocopy, com os códigos 0–7 tratados como sucesso |
| Impressão digital SHA-256 | manifesto gerado e conferido, ida e volta |
| Estrutura CH.Com no destino | conferida lado a lado contra o padrão do rclone |
| **Enviar para a AWS** | **8 MB subiram, foram conferidos, velocidade medida** |
| Ler o parque do bucket | 5 servidores em 0,7 s, numa chamada só |
| Interface | 5 cenários × 9 telas, todo botão clicado, sem quebra e sem travar |

---

## Codificado, nunca exercitado

Isto é o que me impede de dizer que um cartório está protegido.

| O quê | Por que não foi provado |
|---|---|
| **Restaurar do Deep Archive** | precisa de um backup real lá dentro e de 12 a 48 h de espera |
| **Descongelar** (`backend restore`) | idem — e é o passo que ninguém testa até precisar |
| `Import-VM` no destino | nunca houve um export restaurado em outra máquina |
| `wbadmin start backup` | só existe em Windows Server; a VM de teste é Windows 10 |
| `gbak` no Firebird | não há Firebird instalado em nenhuma máquina de teste |
| `BACKUP DATABASE` no SQL Server | idem |
| Agendamento rodando sozinho de madrugada | nunca houve uma noite completa |

**A restauração é a única coisa que importa de verdade num backup.** Todo o
resto é preparação para ela.

---

## O que fazer, em ordem

### 1. Um backup real, pequeno

Uma pasta de poucos MB, pelo `Executar agora`. Depois, `O que é protegido` →
**Conferir na nuvem**. Isso fecha o ciclo de ida.

### 2. A restauração completa

O que ninguém faz e todo mundo devia:

```
restaurar-cofre.ps1 -Listar
restaurar-cofre.ps1 -Descongelar "<caminho>"        (espera até 48 h)
restaurar-cofre.ps1 -Situacao "<caminho>"
restaurar-cofre.ps1 -Baixar "<caminho>" -Para "D:\teste"
```

Enquanto isso não acontecer uma vez, **não sabemos se o Cofre restaura**.

### 3. Um servidor de verdade

Windows Server com Hyper-V e Firebird. É onde `wbadmin` e `gbak` deixam de
ser teoria. A VM de teste atual é Windows 10: ela faz backup da máquina mas
**não restaura** — o `wbadmin` dela não tem `START SYSRECOVERY`.

### 4. Object Lock no bucket

Ver `aws/COMECAR-NA-AWS.md`. Sem ele, quem invadir o servidor pode apagar o
backup. O agente já não tem permissão de apagar; falta a trava do lado da AWS.

---

## Decisões que valem revisar

**Cada backup é uma cópia inteira.** O destino é `<DISCO>/<AAAA-MM-DD>/`, e
nada é reaproveitado entre datas. Isso dá pontos de recuperação independentes
— um não depende do outro — e custa upload cheio toda vez. Numa VM de 21 GB
por mês, tudo bem. Numa pasta de 500 GB, não.

**O ciclo de vida do bucket ainda não existe.** Nada apaga cópia velha hoje.
Sem uma regra de expiração, o custo cresce para sempre.
