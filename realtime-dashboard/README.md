# NÃO ESTÁ ENTENDENDO? Faça exatamente isso 👇

## Resposta curta da sua dúvida
**Sim, você vai usar o Terminal.**

Mas é só **copiar e colar 3 comandos**. Nada além disso.

---

## Passo a passo (bem simples)

### 1) Abrir o Terminal
- Linux: procure por **Terminal** no menu.
- Windows: use **PowerShell** ou **Git Bash**.
- Mac: abra **Terminal**.

### 2) Copiar e colar estes comandos (um por linha)

```bash
git clone <URL_DO_REPOSITORIO>
cd CODEX
./iniciar_dashboard.sh
```

> Troque `<URL_DO_REPOSITORIO>` pela URL do seu repositório Git.

### 3) Abrir no navegador
Quando terminar, abra:

- http://localhost:3000

Pronto. Você verá a tela com as tabelas mudando em tempo real.

---

## Importante sobre o erro do `psql`
Se aparecer que `psql` não existe, **agora tudo bem**.
O sistema já tenta automaticamente outro modo (via Node.js), então deve funcionar mesmo sem `psql`.

---


## Se aparecer `invalid escape string`
Esse erro já foi corrigido nas versões mais novas do projeto.
Atualize o repositório e rode novamente:

```bash
cd CODEX
git pull
./iniciar_dashboard.sh
```

## Se aparecer erro de permissão
Copie e cole:

```bash
chmod +x iniciar_dashboard.sh realtime-dashboard/auto_run.sh
./iniciar_dashboard.sh
```

---

## O que esse comando faz sozinho?
O `./iniciar_dashboard.sh` já faz tudo automaticamente:
1. entra na pasta certa,
2. cria `.env`,
3. instala dependências,
4. configura auditoria no banco,
5. liga o dashboard.

---

## Como desligar depois
No terminal onde está rodando, aperte:

- `Ctrl + C`

---

## Se quiser parar a auditoria do banco

```bash
cd CODEX/realtime-dashboard
psql -h localhost -p 5432 -U esus -d esus -f sql/02_remover_triggers.sql
```

---

## Configuração padrão
- Banco: `esus`
- Usuário: `esus`
- Senha: `esus`
- Host: `localhost`
- Porta PostgreSQL: `5432`
- Porta dashboard: `3000`

---


## Se o GitHub mostrar "This branch has conflicts"
No terminal, dentro da pasta do projeto, rode:

```bash
./resolver_conflitos.sh
```

Depois finalize:

```bash
git commit -m "resolve: conflitos do PR"
git push
```
