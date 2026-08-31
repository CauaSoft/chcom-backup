# CH.Com Cofre

**A cópia que fica fora.** Disaster recovery para servidores de cartório, em
S3 Glacier Deep Archive, sem licença comercial nenhuma.

Não substitui o backup local — existe para o caso de perda total: incêndio,
roubo, ou os servidores irem embora de uma vez.

---

## O problema

Um provedor de TI que cuida de dezenas de cartórios tem backup local em todos
eles. O que não tem é a cópia **fora do prédio** — e é ela que decide se o
cartório volta a funcionar depois de um desastre.

As soluções que fazem isso direito custam por servidor. Multiplicado por 50
cartórios, vira uma conta que não fecha.

## A ideia

O Windows já sabe fazer as partes difíceis. Falta alguém orquestrar.

```
   SERVIDOR                     O QUE O WINDOWS JÁ FAZ
   ────────                     ──────────────────────
   host Hyper-V      ──────▶    Export-VM com production checkpoint
                                (VSS dentro da VM, sem desligar nada)
                     ──────▶    wbadmin -allCritical
                                (o host: sistema, switches, config)

   servidor físico   ──────▶    wbadmin -allCritical
                                (recuperação bare metal)

   Firebird          ──────▶    gbak
   SQL Server        ──────▶    BACKUP DATABASE + RESTORE VERIFYONLY
   discos e pastas   ──────▶    cópia de sombra (VSS de volume)
                                       │
                                       ▼
                              VALIDAÇÃO ANTES DE SUBIR
                              Compare-VM · gbak -c · SHA-256
                                       │
                                       ▼
                              rclone crypt  (AES-256, aqui)
                                       │
                                       ▼
                              S3 Glacier Deep Archive
                              (~US$ 1 por TB por mês)
```

Tudo nativo ou open source. O único componente de terceiro é o
[rclone](https://rclone.org) (licença MIT), que faz criptografia e transporte.

---

## O agente decide sozinho

Não há configuração por cartório. Ele olha o servidor e monta o plano:

```
  Plano para esta maquina: host Hyper-V
      MAQUINA VIRTUAL      VM-SISTEMA
         mensal - Export-VM com production checkpoint (application-consistent)
      MAQUINA VIRTUAL      VM-ARQUIVOS
         mensal - SEM production checkpoint - vai sair CRASH-CONSISTENT
      IMAGEM DO SERVIDOR   Host CARTORIO-01 (sistema e config do Hyper-V)
         mensal - wbadmin -allCritical
      BANCO FIREBIRD       C:\Firebird\3.0
         diaria - gbak: copiar o .fdb aberto nao e backup valido
```

Repare na segunda VM. Ela vai subir, vai ficar verde — e o plano **diz na cara**
que sai crash-consistent, porque faltam os Serviços de Integração dentro dela.
Um backup com promessa e um backup com torcida não são a mesma luz verde.

---

## Três decisões que definem o projeto

### Nada sobe sem ser conferido antes

`Compare-VM` confirma que o export é importável. `gbak -c` restaura o `.fbk`
num banco descartável. `RESTORE VERIFYONLY` lê o `.bak` inteiro. E cada
arquivo ganha uma impressão digital SHA-256, gravada num manifesto que viaja
junto — e é conferida de volta na restauração.

Conferir depois não serve: em Deep Archive, ler o que já subiu custa dinheiro
e leva de 12 a 48 horas. A única hora barata de conferir é enquanto o arquivo
ainda está no disco local.

### Deep Archive direto, sem regra de ciclo de vida

A lifecycle rule do S3 filtra por prefixo, **não por final de nome**. Com ela,
os índices congelam junto com os dados — e recuperar um arquivo de 10 KB
exigiria descongelar o repositório inteiro.

O rclone grava a classe no próprio envio, e cada cópia fica independente das
outras. Perder uma não afeta as demais.

### O motor e a interface são dois programas

Backup de cartório roda às 2 da manhã, sem ninguém na frente. Um backup que
morre quando alguém fecha a janela não é backup.

O motor escreve `estado.json` a cada passo; a janela lê e desenha. Fechar a
janela não interrompe nada, e um erro de tela nunca custa o backup de um
cartório.

---

## A chave

Tudo é cifrado no servidor antes de sair. **Sem a chave, o que está na AWS é
lixo irrecuperável** — nem a Amazon, nem quem tiver a senha da conta consegue
ler.

Por isso o assistente **não deixa continuar** enquanto a chave não for
guardada fora do cartório. Se ela existir só no servidor e o servidor for
destruído — que é o cenário exato para o qual o Cofre existe — o backup morre
junto.

---

## Instalação

1. Descompacte o pacote no servidor
2. Dois cliques em `INSTALAR.bat`
3. O assistente cuida do resto: destino, chave, teste real contra a AWS,
   e o agendamento

Antes disso, é preciso ter na AWS um bucket e um usuário IAM. O `LEIA-ME.txt`
do pacote traz a política pronta para copiar — inclusive o `s3:RestoreObject`,
sem o qual o backup **sobe e nunca volta**.

## Recuperação

Leia [`docs/RESTAURAR-DO-COFRE.txt`](docs/RESTAURAR-DO-COFRE.txt) **antes** de
precisar. No dia em que precisar, ninguém tem cabeça para aprender
procedimento novo.

O ponto que pega as pessoas de surpresa: Deep Archive não é imediato.
Recuperar exige pedir o descongelamento e esperar de 12 a 48 horas. Isso não
tem como acelerar, e quem promete restauração imediata de Deep Archive está
enganando alguém.

---

## Estado

Construído e verificado; **ainda não exercitado contra a AWS de produção**.
O assistente testa a conexão sozinho na primeira instalação — sobe 8 MB,
confere, apaga e mede o link real.

## Licença

MIT. Usa o [rclone](https://rclone.org) (MIT) para criptografia e transporte.
