---
name: generate
description: Generate the complete standard documentation package for any full-stack project. Creates user manual, admin manual, and developer handoff docs by analyzing the actual codebase.
---

# doc-standard:generate

Generate a complete, standardized documentation package for the current project by analyzing the actual codebase.

**This skill is fully project-agnostic.** All content is derived from the codebase — nothing is hardcoded.

## Output Structure

The skill generates this documentation tree:

```
docs/
├── manual-usuario.md          # End-user manual (Portuguese)
├── manual-administrador.md    # Admin/ops manual (Portuguese)
└── documentation/
    ├── README.md              # Index of technical docs
    ├── arquitetura.md         # Architecture, stack, auth, infra
    ├── modelos-banco.md       # All DB models with fields + ER diagram
    ├── api-endpoints.md       # All API endpoints by module with permissions
    ├── frontend-estrutura.md  # Pages, components, hooks, services, types
    ├── regras-negocio.md      # Critical business rules and gotchas
    └── setup-desenvolvimento.md  # Dev environment setup guide
```

## Flow

Follow these steps in order. Do NOT skip any step.

### Step 1: Discover Project

Analyze the project to understand its stack and structure:

```
1. Read CLAUDE.md (if exists) for project-specific conventions
2. Read README.md (if exists) for existing documentation
3. List root directory to identify stack (backend/, frontend/, docker-compose files, etc.)
4. Identify the tech stack:
   - Backend language/framework (Python/FastAPI, Node/Express, Go, etc.)
   - Frontend framework (React, Vue, Angular, etc.)
   - Database (PostgreSQL, MySQL, MongoDB, etc.)
   - Infrastructure (Docker, K8s, etc.)
```

### Step 2: Inventory the Codebase

Gather comprehensive data about every module. Adapt paths based on the stack discovered in Step 1.

**Backend inventory:**
```
- List all model/entity files → extract class names, key fields, relationships
- List all API/route/controller files → extract route prefixes, endpoint count, HTTP methods
- List all schema/DTO/serializer files → extract validation rules
- List all service/business-logic files → extract key functions
- List config/settings files → extract env vars, auth config, CORS
- List migration files → count, latest migration
```

**Frontend inventory:**
```
- List all page/view files → extract component names, line counts
- List all reusable component files → extract props, purpose
- List all hooks/composables → extract names, purpose
- List all state management (stores/context) → extract state shape
- List all API client/service files → extract service functions
- List all type/interface files → extract key types
- List routing config → extract routes and guards
```

**Infrastructure inventory:**
```
- Docker files (Dockerfile, docker-compose) → extract services, ports, volumes
- Nginx/reverse proxy config → extract routing rules
- Deploy scripts → extract deploy flow
- CI/CD config → extract pipeline steps
- SSL/TLS config → extract certificate management
```

### Step 3: Identify Business Rules

Search for critical patterns in the codebase:

```
1. Grep for validation logic (raise, throw, Error, HTTPException, abort)
2. Grep for status/state machines (enum, status, state, transition)
3. Grep for cross-entity validation (checking one entity before modifying another)
4. Read service layer functions for business logic
5. Check for calculated/computed fields in responses
6. Check for cascade operations (updating children when parent changes)
7. Check for permission/authorization checks beyond basic RBAC
```

### Step 4: Generate Documentation

Create all 9 files using subagents for parallelism when possible. Each document MUST be:

- Written in **Portuguese (pt-BR)** for prose, English for code examples
- Based on **actual code analysis**, not assumptions
- **Accurate** — every model field, endpoint, and component must match the codebase
- **Complete** — cover ALL modules, not just the main ones

#### 4.1: Manual do Usuário (`docs/manual-usuario.md`)

Target audience: **operational staff using the system daily**.

Structure:
```markdown
# Manual do Usuário — [NOME DO SISTEMA]

## 1. Introdução ao Sistema
   - O que o sistema faz
   - Perfis de acesso (listar todos com descrição)
   - Tabela de permissões por perfil

## 2. Acesso e Login
   - URL de acesso
   - Fluxo de login
   - Sessão e timeout
   - Troca de senha

## 3-N. [Um capítulo por módulo/página]
   Para cada módulo:
   - O que é e para que serve
   - Como acessar (menu)
   - Operações disponíveis (criar, editar, excluir, exportar)
   - Campos do formulário com descrição
   - Regras de negócio relevantes para o usuário
   - Dicas e atalhos

## Último. Referência Rápida
   - Tabela de status e seus significados
   - Tabela de perfis e permissões
   - FAQ operacional
```

#### 4.2: Manual do Administrador (`docs/manual-administrador.md`)

Target audience: **sysadmin responsible for production environment**.

Structure:
```markdown
# Manual do Administrador — [NOME DO SISTEMA]

## 1. Visão Geral da Infraestrutura
   - Diagrama de containers/serviços
   - Portas e recursos

## 2. Requisitos do Servidor
   - Hardware mínimo
   - Software necessário
   - Portas de firewall

## 3. Instalação e Configuração Inicial
   - Passo a passo do zero

## 4. Variáveis de Ambiente
   - Todas as variáveis com descrição e valores exemplo

## 5. Deploy em Produção
   - Fluxo do deploy script
   - Deploy manual vs automatizado
   - Rollback

## 6. Migrações de Banco de Dados
   - Comandos
   - Regras de segurança (nunca DROP em produção)
   - Padrão de migração segura (nullable → update → not null)

## 7. Certificado SSL
   - Obtenção e renovação

## 8. Gestão de Usuários e Permissões
   - Criação de usuários
   - Perfis disponíveis

## 9. Backup e Restauração
   - Manual, automatizado, restore

## 10. Monitoramento e Logs
   - Comandos de log por container
   - Health checks

## 11. Troubleshooting
   - Cenários comuns com comandos exatos

## 12. Segurança
   - Auth, CORS, rate limiting, firewall
```

#### 4.3: Documentação Técnica (`docs/documentation/`)

Target audience: **developers taking over the project**.

**README.md** — Index with reading order by profile (new dev, feature dev, tech lead).

**arquitetura.md** — Stack completo com versões, diagrama de containers, fluxo de auth, state management, estrutura de diretórios, proxy reverso.

**modelos-banco.md** — EVERY model with:
```markdown
### NomeDoModelo
| Campo | Tipo | Constraints | Descrição |
|-------|------|------------|-----------|
| id    | Integer | PK, auto  | ...       |

**Relacionamentos:** ...
**Enums:** ...
```
End with text-based ER diagram describing all relationships.

**api-endpoints.md** — EVERY endpoint with:
```markdown
### Módulo (prefix: /api/modulo)
| Método | Rota | Permissão | Descrição |
|--------|------|-----------|-----------|
| GET    | /    | all       | Listar    |
```
Include query parameters, special behaviors, response format notes.

**frontend-estrutura.md** — ALL pages with line count, ALL components with props, hooks, stores, services, types, routing, permission system, UI framework config, responsive strategy. End with "checklist para adicionar nova página".

**regras-negocio.md** — ALL critical business rules discovered in Step 3, organized by severity. For each rule:
```markdown
### Regra: [Título]
**Severidade:** Crítica/Alta/Média
**Onde:** [arquivo:função]
**Regra:** [Descrição clara]
**Por que existe:** [Contexto/incidente que motivou]
**Como verificar:** [Comando ou teste]
```

**setup-desenvolvimento.md** — Step-by-step from clone to running app. Include: prerequisites, clone, env files, docker commands, migrations, seed data, URLs, daily commands, git workflow, common problems with solutions.

### Step 5: Validate

After generating all files:

```
1. Count total files created (should be 9)
2. Verify each file has content (not empty)
3. Cross-reference: every model in modelos-banco.md must appear in api-endpoints.md
4. Cross-reference: every page in frontend-estrutura.md must appear in manual-usuario.md
5. Report summary to user with file sizes
```

### Step 6: Commit

```bash
git add docs/manual-usuario.md docs/manual-administrador.md docs/documentation/
git commit -m "docs: Gerar pacote de documentação padrão (manual usuário, admin, handoff técnico)"
```

## Quality Checklist

Before declaring the skill complete, verify:

- [ ] All 9 files created and non-empty
- [ ] All models documented in modelos-banco.md
- [ ] All endpoints documented in api-endpoints.md
- [ ] All pages documented in frontend-estrutura.md and manual-usuario.md
- [ ] All env vars documented in manual-administrador.md
- [ ] Business rules include file:function references
- [ ] Setup guide includes all docker/migration commands from actual config files
- [ ] No placeholder text ("TODO", "TBD", "[fill in]") remains

## Notes

- Use subagents to parallelize the 3 main doc groups (user manual, admin manual, technical docs)
- Prefer Serena MCP tools for codebase exploration (get_symbols_overview, list_dir) when available
- If the project has existing docs/, read them first to avoid contradictions
- Always generate in Portuguese (pt-BR) for prose content
- Do NOT include emojis unless the project's existing docs use them
- The skill adapts to any stack — the inventory step discovers what exists
