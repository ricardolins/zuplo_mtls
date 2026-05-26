# Zuplo — Setup Completo, CLI e Developer Portal

Este documento cobre tudo que foi configurado e corrigido no Zuplo: projeto, políticas, rotas, developer portal (Zudoku) e deploy via CLI.

---

## Visão Geral da Arquitetura Zuplo

```
Partner/Client
    │
    ▼
https://mtls-main-6012973.zuplo.app   ← API Gateway (Cloudflare Edge)
https://mtls-main-6012973.zuplo.site  ← Developer Portal (Zudoku/SSR)
    │
    ▼
Políticas inbound (autenticação, validação)
    │
    ├── CERT_SERVICE_URL → Certificate Service no LKE
    └── BACKEND_API_URL  → Backend API no LKE
```

**Contas e projeto:**
- Conta Zuplo: `turquoise_dear_chipmunk`
- Projeto: `mtls`
- Environment: `main`
- API Key Bucket (produção): `bckt_9bbsIcTU4Ow8Mz25EIvKCS5Zb3NQbRwC`

---

## Estrutura do Projeto Zuplo

```
zuplo/
├── .zupignore              # O que excluir do tarball de deploy
├── zuplo.jsonc             # Config principal (versão, compatibilidade)
├── package.json            # Dependências (zuplo ^6), workspaces
├── tsconfig.json           # TypeScript para os módulos
├── config/
│   ├── routes.oas.json     # Rotas OpenAPI 3.1 + políticas por rota
│   └── policies.json       # Definição de todas as políticas
├── modules/
│   ├── api-key-policy.ts   # Política custom: valida API Key Zuplo + extrai tenant
│   ├── mtls-policy.ts      # Política custom: lê certificado mTLS do header
│   └── cert-validation-policy.ts  # Política custom: valida certificado contra serviço
└── docs/
    ├── zudoku.config.ts    # Config do Developer Portal (Zudoku)
    ├── tsconfig.json       # TypeScript config do Zudoku
    ├── package.json        # Deps do portal (zudoku ^0.79, react, etc.)
    ├── package-lock.json
    └── pages/
        ├── getting-started.md    # Página "Getting Started"
        └── certificate-guide.md  # Página "Certificate Guide"
```

---

## CLI — Instalação e Autenticação

### Binário local (IMPORTANTE)

O `npx zuplo` falha com erro de permissão no cache npm root-owned (`~/.npm/_cacache/`).
**Sempre usar o binário local:**

```bash
# Dentro do diretório zuplo/
node_modules/.bin/zuplo <comando>
```

### Autenticação

```bash
# Fazer login (abre browser)
node_modules/.bin/zuplo login

# Verificar quem está autenticado
node_modules/.bin/zuplo whoami
# → Authenticated as auth0|68c82cd07c755f4851a6f122

# Ver todos os comandos disponíveis
node_modules/.bin/zuplo --help
```

### Deploy

```bash
# Deploy para o environment "main"
# (Em ambientes não-interativos, --account e --project são obrigatórios)
node_modules/.bin/zuplo deploy \
  --account turquoise_dear_chipmunk \
  --project mtls

# Com verbose para debug
node_modules/.bin/zuplo deploy \
  --account turquoise_dear_chipmunk \
  --project mtls \
  -vv
```

**Output esperado:**
```
- Deploying the 'main' environment to 'mtls' on account 'turquoise_dear_chipmunk'...
✔ Deployed to https://mtls-main-6012973.zuplo.app (XX/250)
```

O número `(XX/250)` é o índice do build — quanto mais baixo, mais rápido foi o build.

### Outros comandos úteis

```bash
# Listar projetos deployados
node_modules/.bin/zuplo list --account turquoise_dear_chipmunk

# Rodar localmente (dev mode)
node_modules/.bin/zuplo dev

# Rodar o Developer Portal localmente
node_modules/.bin/zuplo docs

# Gerenciar variáveis de ambiente
node_modules/.bin/zuplo variable list --account turquoise_dear_chipmunk --project mtls
node_modules/.bin/zuplo variable set MY_VAR "value" --account ... --project ...

# Gerenciar API Key Buckets
node_modules/.bin/zuplo bucket list --account turquoise_dear_chipmunk --project mtls

# Gerenciar túneis (para conectar gateway ao cluster privado)
node_modules/.bin/zuplo tunnel list --account turquoise_dear_chipmunk --project mtls

# Gerenciar certificados CA (para mTLS inbound)
node_modules/.bin/zuplo ca-certificate list --account turquoise_dear_chipmunk --project mtls

# Informações do projeto
node_modules/.bin/zuplo info --account turquoise_dear_chipmunk --project mtls
```

---

## .zupignore

O `.zupignore` funciona como `.gitignore`: define o que **excluir** do tarball enviado ao Zuplo.

**ATENÇÃO:** Quando o arquivo existe, ele **substitui completamente** os defaults — é preciso re-listar explicitamente `.git/` e `node_modules/`.

```gitignore
.git/
node_modules/
docs/node_modules/    ← Apenas o node_modules do portal, não o docs/ inteiro
dist/
.zuplo/build.json
.zuplo/worker.ts
```

**Erro anterior:** `docs/` estava listado inteiro, o que excluía os arquivos de configuração do portal (`zudoku.config.ts`, `pages/`). Correto é excluir apenas `docs/node_modules/`.

---

## Variáveis de Ambiente

Configuradas no Zuplo Dashboard ou via CLI, referenciadas nos handlers como `${env.NOME}`:

| Variável         | Uso                                               |
|------------------|---------------------------------------------------|
| `CERT_SERVICE_URL` | URL base do Certificate Service no LKE          |
| `BACKEND_API_URL`  | URL base do Backend API no LKE                  |

---

## Políticas — `config/policies.json`

### Fluxo de autenticação por rota

```
Bootstrap (sem auth)
  /v1/tenants POST  ──────────────────────────────→ rate-limit

API Key (emisão de certificados)
  /v1/certificates POST/GET  ─→ zuplo-api-key-auth → api-key-inbound → rate-limit
  /v1/certificates/{id} GET  ─→ zuplo-api-key-auth → api-key-inbound

mTLS (operações protegidas)
  /v1/certificates/{id} DELETE  ─→ mtls-inbound → cert-validation
  /v1/certificates/{id}/renew   ─→ mtls-inbound → cert-validation
  /v1/api/{path} GET/POST       ─→ mtls-inbound → cert-validation → rate-limit
```

### Políticas definidas

**1. `zuplo-api-key-auth-policy`** — Valida API Key via bucket Zuplo

```json
{
  "name": "zuplo-api-key-auth-policy",
  "policyType": "api-key-inbound",
  "handler": {
    "export": "ApiKeyInboundPolicy",
    "module": "$import(@zuplo/runtime)",
    "options": {
      "authHeader": "X-API-Key",
      "authScheme": ""
    }
  }
}
```

*Correção aplicada:* `export` era `"default"` (incorreto). Correto: `"ApiKeyInboundPolicy"`. Também foi necessário adicionar `options.authHeader` e `options.authScheme` — sem eles, o policy retornava erro de `bucketId undefined`.

**2. `api-key-inbound-policy`** — Extrai tenant ID da API Key validada

```json
{
  "name": "api-key-inbound-policy",
  "policyType": "custom-code-inbound",
  "handler": {
    "export": "apiKeyInboundPolicy",
    "module": "$import(./modules/api-key-policy)"
  }
}
```

*Correção aplicada:* Caminho era `$import(../modules/api-key-policy)`. O esbuild resolve a partir da raiz do projeto, não do diretório `config/`. Correto: `$import(./modules/api-key-policy)`.

**3. `mtls-inbound-policy`** — Lê e parseia o certificado mTLS do header

```json
{
  "name": "mtls-inbound-policy",
  "policyType": "custom-code-inbound",
  "handler": {
    "export": "mtlsInboundPolicy",
    "module": "$import(./modules/mtls-policy)"
  }
}
```

**4. `cert-validation-policy`** — Valida o certificado contra o serviço de PKI

```json
{
  "name": "cert-validation-policy",
  "policyType": "custom-code-inbound",
  "handler": {
    "export": "certValidationPolicy",
    "module": "$import(./modules/cert-validation-policy)"
  }
}
```

**5. `rate-limit-policy`** — Rate limiting por IP

```json
{
  "name": "rate-limit-policy",
  "policyType": "rate-limit-inbound",
  "handler": {
    "export": "RateLimitInboundPolicy",
    "module": "$import(@zuplo/runtime)",
    "options": {
      "rateLimitBy": "ip",
      "requestsAllowed": 100,
      "timeWindowMinutes": 1
    }
  }
}
```

*Correção aplicada:* `export` era `"default"` (incorreto). Correto: `"RateLimitInboundPolicy"`.

---

## Rotas — `config/routes.oas.json`

OpenAPI 3.1 com extensões Zuplo (`x-zuplo-path`, `x-zuplo-route`).

### Endpoints configurados

| Método | Path | Auth | Políticas |
|--------|------|------|-----------|
| `POST` | `/v1/tenants` | Nenhuma | rate-limit |
| `POST` | `/v1/certificates` | API Key | zuplo-api-key-auth, api-key-inbound, rate-limit |
| `GET` | `/v1/certificates` | API Key | zuplo-api-key-auth, api-key-inbound, rate-limit |
| `GET` | `/v1/certificates/{id}` | API Key | zuplo-api-key-auth, api-key-inbound |
| `DELETE` | `/v1/certificates/{id}` | mTLS | mtls-inbound, cert-validation |
| `POST` | `/v1/certificates/{id}/renew` | mTLS | mtls-inbound, cert-validation |
| `GET` | `/v1/api/{path}` | mTLS | mtls-inbound, cert-validation, rate-limit |
| `POST` | `/v1/api/{path}` | mTLS | mtls-inbound, cert-validation, rate-limit |

Todos os handlers usam `urlForwardHandler` do runtime Zuplo, fazendo proxy para as variáveis de ambiente `CERT_SERVICE_URL` ou `BACKEND_API_URL`.

---

## Developer Portal — Zudoku

### O que é o Zudoku

O Zudoku é o framework de developer portal do Zuplo. Quando incluído no projeto, o Zuplo **gerencia o build, deploy e hosting** automaticamente. O portal é servido em:

```
https://{projeto}-{environment}-{id}.zuplo.site
```

Para este projeto: `https://mtls-main-6012973.zuplo.site`

### Como o build funciona

1. O `zuplo deploy` empacota o projeto (respeitando `.zupignore`)
2. Zuplo detecta o diretório `docs/` como Developer Portal
3. Executa `npm run build` dentro de `docs/` → `zudoku build --zuplo`
4. O Zudoku faz SSR (Server-Side Rendering) + prerendering de todas as rotas
5. O resultado é servido via CloudFront

### Arquivos necessários

**`docs/package.json`** — dependências do portal:
```json
{
  "name": "mtls-baas-portal",
  "version": "0.1.0",
  "type": "module",
  "private": true,
  "scripts": {
    "dev": "zudoku dev --zuplo",
    "build": "zudoku build --zuplo"
  },
  "dependencies": {
    "react": "^19.0.0",
    "react-dom": "^19.0.0",
    "zudoku": "^0.79.0"
  },
  "devDependencies": {
    "@types/node": "^22",
    "@types/react": "^19",
    "@types/react-dom": "^19",
    "typescript": "^5"
  }
}
```

**`docs/tsconfig.json`** — TypeScript config para o Zudoku:
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "jsx": "react-jsx",
    "strict": true,
    "skipLibCheck": true
  }
}
```

**`docs/zudoku.config.ts`** — configuração principal do portal:
```typescript
import type { ZudokuConfig } from "zudoku";

const config: ZudokuConfig = {
  metadata: { title: "BaaS mTLS Platform" },
  site: { title: "BaaS mTLS Platform" },
  docs: {
    files: "/pages/**/*.{md,mdx}",   // glob relativo à raiz de docs/
  },
  navigation: [
    {
      type: "category",
      label: "Documentation",
      items: [
        { type: "link", label: "Getting Started", to: "/getting-started" },
        { type: "link", label: "Certificate Guide", to: "/certificate-guide" },
      ],
    },
    { type: "link", label: "API Reference", to: "/api-reference" },
  ],
  apis: [
    {
      type: "file",
      input: "../config/routes.oas.json",  // relativo à raiz de docs/
      path: "/api-reference",
    },
  ],
  redirects: [{ from: "/", to: "/api-reference" }],
};

export default config;
```

### Problemas encontrados e soluções

#### 1. "Environment Not Found" no `zuplo.site`

**Causa:** `docs/` estava listado inteiro no `.zupignore`, excluindo todos os arquivos do portal do tarball de deploy. O Zuplo recebia o projeto sem a pasta `docs/` e não conseguia construir o portal.

**Solução:** Trocar `docs/` por `docs/node_modules/` no `.zupignore` — exclui apenas o `node_modules` pesado, mantém os arquivos de configuração.

#### 2. Build falha com `ZudokuError: Authentication is not enabled`

**Causa:** A configuração original tinha `apiKeys: { enabled: true }`, que cria uma rota `/settings/api-keys` protegida. Durante o prerendering SSR, o Zudoku tentava renderizar essa rota mas falhava porque nenhum provider de autenticação estava configurado.

**Stack trace relevante:**
```
SSR Error (GET http://localhost/settings/api-keys): ZudokuError: Authentication is not enabled
developerHint: 'To use protectedRoutes you need authentication to be enabled'
```

**Solução:** Remover `apiKeys: { enabled: true }` do config. Para habilitá-lo no futuro, é necessário configurar um auth provider (Auth0, Clerk, etc.) antes.

#### 3. Páginas de documentação retornam 404

**Causa (parte 1):** Faltava o campo `docs.files` na configuração. Sem ele, o Zudoku não registra as rotas das páginas markdown.

**Causa (parte 2):** O `type: "doc"` com `file: "pages/getting-started"` na navegação gerava links para `/pages/getting-started`, mas o glob `/pages/**/*.{md,mdx}` registrava as rotas sem o prefixo `pages/` → `/getting-started`. URLs não batiam.

**Solução:** Usar `type: "link"` com `to:` explícito na navegação em vez de `type: "doc"` com `file:`. Assim o link aponta exatamente para a URL que o glob registrou:

```typescript
// ❌ Causa mismatch de URL
{ type: "doc", label: "Getting Started", file: "pages/getting-started" }
// → gera link para /pages/getting-started (404)

// ✅ Correto
{ type: "link", label: "Getting Started", to: "/getting-started" }
// → aponta diretamente para a rota registrada pelo glob
```

#### 4. `docs/tsconfig.json` faltando

Sem o `tsconfig.json` dentro de `docs/`, o Zudoku não consegue compilar o `zudoku.config.ts` corretamente. O arquivo é necessário mesmo que simples.

### Rotas do Developer Portal

Após o deploy bem-sucedido, as seguintes rotas ficam disponíveis:

| URL | Descrição |
|-----|-----------|
| `https://mtls-main-6012973.zuplo.site/` | Redireciona para `/api-reference` |
| `https://mtls-main-6012973.zuplo.site/api-reference` | Referência completa de API (gerada do OpenAPI) |
| `https://mtls-main-6012973.zuplo.site/getting-started` | Guia de início rápido |
| `https://mtls-main-6012973.zuplo.site/certificate-guide` | Guia do ciclo de vida dos certificados |

### Desenvolvimento local do portal

```bash
cd zuplo/docs

# Instalar dependências
npm install

# Rodar em modo dev (hot reload)
npm run dev
# → http://localhost:3000

# Build de produção
npm run build
```

Ou via CLI do Zuplo na raiz do projeto:
```bash
cd zuplo
node_modules/.bin/zuplo docs
```

---

## API Keys — Gerenciamento via CLI

O bucket de API Keys de produção (`bckt_9bbsIcTU4Ow8Mz25EIvKCS5Zb3NQbRwC`) é onde ficam as chaves dos tenants.

```bash
# Listar buckets
node_modules/.bin/zuplo bucket list \
  --account turquoise_dear_chipmunk \
  --project mtls

# Criar uma API Key para um novo tenant
node_modules/.bin/zuplo bucket create-key \
  --account turquoise_dear_chipmunk \
  --project mtls \
  --bucket bckt_9bbsIcTU4Ow8Mz25EIvKCS5Zb3NQbRwC \
  --label "Tenant ACME Corp" \
  --consumer "acme-corp"
```

A chave gerada tem o formato `zpka_...` e é fornecida ao parceiro para o fluxo de bootstrap.

---

## Zuplo Tunnel (pendente)

O cluster LKE está protegido pelo Linode Cloud Firewall — só aceita conexões de `177.181.2.218/32`. O Zuplo (que roda na Cloudflare) não consegue alcançar o Certificate Service diretamente.

**Solução necessária: Zuplo Tunnel**

O tunnel instala um agente no cluster que faz conexão *outbound* para o Zuplo — sem precisar abrir regras inbound no firewall.

```bash
# Criar um tunnel
node_modules/.bin/zuplo tunnel create \
  --account turquoise_dear_chipmunk \
  --project mtls \
  --name cert-service-tunnel

# Instalar o agente no cluster (saída do comando anterior gera o manifesto)
kubectl apply -f tunnel-agent.yaml

# Listar tunnels ativos
node_modules/.bin/zuplo tunnel list \
  --account turquoise_dear_chipmunk \
  --project mtls
```

Após o tunnel estar ativo, o `CERT_SERVICE_URL` é trocado pela URL interna do tunnel fornecida pelo Zuplo.

---

## Segurança — Modelo de Proteção

A proteção de acesso **não está no gateway Zuplo** (que é público na Cloudflare). A proteção está na **infraestrutura Linode**:

- **Linode Cloud Firewall (`24456015`)** — bloqueio total de inbound, exceto portas 80/443/6443 do IP `177.181.2.218/32`
- **LKE ACL** — control plane do Kubernetes só aceita `177.181.2.218/32`
- **Zuplo gateway** — público (deve ser assim para parceiros acessarem)

O Zuplo faz a autenticação/autorização via políticas (API Key e mTLS), mas o acesso ao backend real só funciona quando o Zuplo conseguir alcançar o cluster (via Tunnel).

---

## Checklist de Status

- [x] Gateway Zuplo deployado (`https://mtls-main-6012973.zuplo.app`)
- [x] Developer Portal no ar (`https://mtls-main-6012973.zuplo.site`)
- [x] Políticas configuradas (API Key auth, mTLS inbound, rate limit)
- [x] Rotas OpenAPI completas
- [x] Páginas de documentação funcionando
- [x] Linode Firewall bloqueando tudo exceto `177.181.2.218/32`
- [ ] Certificate Service deployado no LKE
- [ ] Zuplo Tunnel configurado (gateway → cluster)
- [ ] Variáveis `CERT_SERVICE_URL` e `BACKEND_API_URL` apontando para túnel
