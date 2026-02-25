# Jira Project Sync Plugin

## Integracao Jira

- **Projeto Jira:** JPSP
- **Sync automatico:** Commits sao sincronizados com Jira automaticamente a cada `git push`
- **Config:** `.claude/jira-sync.json`
- **Estado:** `.claude/jira-sync-state`

### Comportamento do Sync

- Cada push dispara o hook que analisa commits desde o ultimo sync
- Commits sao agrupados semanticamente em cards Jira
- Cards novos sao criados para features/fixes novos
- Commits relacionados a cards existentes sao adicionados como comentarios
- Cards criados sao automaticamente transicionados para Done
