# Por que o motor e a interface sao dois programas

Decisao tomada antes de escrever a interface, e ela molda tudo o que vem
depois.

## O problema

Uma janela em PowerShell roda em uma linha de execucao so. Se o backup rodar
dentro dela, a janela **congela** enquanto exporta uma VM de 80 GB — sem
desenhar, sem responder, sem fechar. O Windows pinta ela de branco e escreve
"nao esta respondendo".

Da para contornar com runspaces e Dispatcher. Mas o contorno traz um problema
pior, e esse nao tem conserto: **se a janela fechar, o backup morre junto**.

Backup de cartorio roda as 2 da manha, sem ninguem na frente. Um backup que
depende de uma janela aberta nao e backup.

## A decisao

Dois programas, com um arquivo de estado entre eles.

```
   cofre.ps1               estado.json            CH.Com Cofre.exe
   (o motor)         →   (o que esta      ←      (a interface)
   roda agendado          acontecendo)            roda quando alguem abre
   sem interface
```

O motor nao sabe que existe interface. Escreve o que esta fazendo num arquivo
JSON a cada passo. A interface le esse arquivo e desenha.

## O que isso da de graca

- **O backup roda sem ninguem.** Agendador do Windows chama o motor direto.
- **Fechar a janela nao para nada.** Da para abrir, ver, e fechar no meio.
- **Abrir a janela depois mostra o que aconteceu.** O estado esta no arquivo,
  nao na memoria de um processo que ja morreu.
- **Duas pessoas podem olhar ao mesmo tempo** — o tecnico por acesso remoto e
  o gerente no console.
- **A interface pode quebrar sem derrubar o backup.** Um erro de tela nao
  pode custar o backup de um cartorio.

## O preco

A interface nao manda no motor diretamente: ela pede, escrevendo um arquivo
de comando, e o motor obedece quando le. Isso significa um atraso de ate um
segundo entre clicar e acontecer. E aceitavel — e muito mais barato que a
alternativa.
