# Capítulo 3 — Rego para autorização de API

> Aqui a missão ganha carne: definimos o **contrato de entrada** (`input`) entre o servidor MCP (PEP) e o OPA (PDP), montamos **RBAC** (papéis) + **ABAC** (contexto e argumentos), validamos **JWT** e produzimos decisões **ricas** (`allow` + `reasons`). No fim do capítulo existe uma política completa de um MCP de faturamento — a mesma que o projeto final (capítulo 6) usa no EKS.

## 🎯 Objetivos

- Desenhar o **`input`** de uma chamada de ferramenta MCP (o contrato PEP↔PDP);
- Implementar **RBAC** (quem tem qual papel → o que pode fazer) em Rego;
- Implementar **ABAC** (projeto, valor, ambiente, horário) sobre o RBAC;
- Validar e extrair **JWT** dentro do OPA (`io.jwt.*`) — ou consumir claims já validadas;
- Produzir decisões **explicáveis**: `allow`, `reasons`, e o objeto de resposta canônico;
- Autorizar pelos **argumentos da ferramenta** — o superpoder do modelo para MCPs.

## 📖 Conteúdo

### 3.1 O contrato: o que vai no `input`

O PEP monta o `input` a cada chamada. Ele deve conter **tudo que a decisão precisa** — e nada além. Para uma chamada de ferramenta MCP, o shape usado no resto do curso ([padrão do tutorial oficial de autorização do OPA](https://www.openpolicyagent.org/docs/latest/authorization/)):

```json
{
  "token": "eyJhbGciOi...",                     // 1. o bearer token cru (se o OPA for validar)
  "chamada": {
    "ferramenta": "emitir_reembolso",           // 2. qual ferramenta MCP
    "argumentos": {
      "projeto_id": "proj-41",
      "valor": 450.00,
      "moeda": "BRL"
    }
  },
  "contexto": {
    "origem": "mcp-faturamento",                // 3. metadados da chamada
    "ambiente": "prod",
    "hora": "2026-10-16T14:30:00Z"
  }
}
```

> 💡 **Regra de ouro:** o OPA só conhece o que está no `input` e no `data`. Se a política precisa saber "a que equipe pertence o projeto proj-41", isso vem do `data` (sincronizado via bundle — capítulo 4) ou entra no `input` (enriquecido pelo PEP). O OPA **não consulta banco** sozinho.

### 3.2 RBAC: papéis e permissões no `data`

RBAC mapeia *papéis → permissões* e *usuários → papéis*. Os mapeamentos são **dados** (mudam sem tocar na política); a mecânica é **política**:

```json
// data.json — carregado no OPA
{
  "rbac": {
    "vinculos": {
      "ana@empresa.com": ["financeiro", "auditor"],
      "bruno@empresa.com": ["engenharia"]
    },
    "papeis": {
      "financeiro": {
        "permissoes": [
          {"ferramenta": "listar_faturas",   "efeito": "permitir"},
          {"ferramenta": "ver_reembolso",    "efeito": "permitir"},
          {"ferramenta": "emitir_reembolso", "efeito": "permitir"}
        ]
      },
      "admin_financeiro": {
        "permissoes": [
          {"ferramenta": "*", "efeito": "permitir"}
        ]
      }
    }
  }
}
```

A mecânica em Rego (arquivo `mcp_autorizacao.rego`):

```rego
package mcp.autorizacao

import rego.v1

default allow := false

# ---- identidade extraída do token (seção 3.4) ----
usuario := payload.sub if {
    [valido, _, payload] := io.jwt.decode(input.token)   # sem verificar assinatura — ver 3.4
    valido
}

# ---- RBAC: usuário tem papel que concede a ferramenta ----
allow if {
    some papel in data.rbac.vinculos[usuario]
    some permissao in data.rbac.papeis[papel].permissoes
    permissao.efeito == "permitir"
    ferramenta_concede(permissao.ferramenta)
}

ferramenta_concede(padrao) if padrao == "*"
ferramenta_concede(padrao) if padrao == input.chamada.ferramenta
```

Leia em voz alta: *"permita se: existe um papel do usuário cuja permissão cubra a ferramenta chamada"*. O `*` do `admin_financeiro` é só um padrão a mais — RBAC inteiro em ~15 linhas.

### 3.3 ABAC: contexto e atributos

RBAC responde *"qual papel pode o quê"*; ABAC adiciona *"sob quais condições"* — e é onde os limites reais dos MCPs vivem ([guião ABAC do OPA](https://www.openpolicyagent.org/docs/latest/authorization-policy/)):

```rego
#_continuação do mesmo package_

# ---- limite por valor (o argumento entra na decisão!) ----
limite_respeitado if {
    input.chamada.ferramenta != "emitir_reembolso"
}
limite_respeitado if {
    input.chamada.ferramenta == "emitir_reembolso"
    input.chamada.argumentos.valor <= data.limites[input.contexto.ambiente].reembolso_max
}

# ---- janela de operação (ex.: fechamento contábil) ----
horario_permitido if {
    input.contexto.ambiente == "dev"
}
horario_permitido if {
    input.contexto.ambiente == "prod"
    time.parse_rfc3339_ns(input.contexto.hora) >= time.parse_rfc3339_ns("2026-10-16T00:00:00Z")
    not fim_de_semana
}

# ---- e a porta de entrada única: ----
allow if {                      # segunda rule de allow = OR com a do RBAC? NÃO — substitua:
    rbac_ok                     # a prática: fatore em rules nomeadas e exija todas
    limite_respeitado
    horario_permitido
}

rbac_ok if {
    some papel in data.rbac.vinculos[usuario]
    some permissao in data.rbac.papeis[papel].permissoes
    permissao.efeito == "permitir"
    ferramenta_concede(permissao.ferramenta)
}
```

> ⚠️ **Refatoração importante:** quando surgem condições transversais (limite, horário), não deixe múltiplas rules `allow` espalhadas — fatore cada dimensão numa rule nomeada (`rbac_ok`, `limite_respeitado`…) e mantenha **uma única** rule `allow` que exige todas. A política vira uma tabela de decisão legível.

Padrões ABAC que aparecem em MCPs:

| Dimensão | Exemplo no input/data | Rego típico |
|---|---|---|
| **Recurso/tenant** | `argumentos.projeto_id` × `data.projetos[..].dono` | `data.projetos[arg.projeto_id].equipe == payload.equipe` |
| **Valor/tamanho** | `argumentos.valor` | `arg.valor <= data.limites[amb].max` |
| **Ambiente** | `contexto.ambiente` | `input.contexto.ambiente == "prod"` |
| **Horário/janela** | `contexto.hora` | `time.parse_rfc3339_ns(...) in janela` |
| **Confiança do agente** | claim `agent_id` no token | `payload.agent_id in data.agentes_aprovados` |

### 3.4 JWT: autenticação dentro (ou fora) do OPA

Para decidir, precisamos confiar em **quem** chama. Duas arquiteturas ([docs — JWT](https://www.openpolicyagent.org/docs/latest/jwt/)):

**Opção A — O PEP valida o token; o OPA recebe claims.** O gateway/servidor MCP valida assinatura, expiração e audience (ex.: middleware OAuth 2.1 do MCP), e injeta as claims já confiáveis no `input`:

```json
{ "claims": { "sub": "ana@empresa.com", "scope": "mcp:faturamento", "equipe": "financeiro" } }
```

```rego
usuario := input.claims.sub
```

Mais simples; a validação criptográfica fica onde já existem bibliotecas maduras. **É a opção padrão deste curso.**

**Opção B — O OPA valida o token.** A política verifica assinatura/expiração/audience e ainda **decora** a decisão com claims. Para HMAC (HS256):

```rego
token_valido if {
    io.jwt.verify_hs256(input.token, data.segredos.hmac)      # assinatura
}

claims := payload if {
    token_valido
    [true, _, payload] := io.jwt.decode_verify(input.token, {  # + exp/aud/iss
        "aud": ["mcp-faturamento"],
        "iss": "https://id.empresa.com",
    })
}
```

Para **RS256/ES256** (chave pública — o comum com Authorization Servers OAuth 2.1 como o da spec MCP), o caminho comum é `io.jwt.verify_rs256(token, certificado)` com a chave pública distribuída **via bundle** ( JWKS embutido no `data` — atualizada quando o AS rotaciona chaves).

```rego
token_valido if {
    some jwk in data.jwks.chaves              # JWKS no data, via bundle
    io.jwt.verify_rs256(input.token, json.marshal(jwk))
}
```

> 💡 **Validar e negar em separado:** faça `default allow := false` e trate token inválido como `deny` com reason própria (`"token_invalido"`). Assinatura inválida ≠ sem permissão — o log de decisão (capítulo 4) vai agradar o time de segurança.

### 3.5 Decisões explicáveis: `allow` + `reasons`

Uma decisão binária força o PEP a responder "não pode" sem porquê. O padrão do curso devolve um **objeto**:

```rego
default decisao := {"allow": false, "reasons": ["sem_vinculo"]}

decisao := {"allow": true, "reasons": []} if {
    rbac_ok
    limite_respeitado
    horario_permitido
}

decisao := {"allow": false, "reasons": reasons} if {
    not rbac_ok
    reasons := ["rbac_negado"]
}

decisao := {"allow": false, "reasons": reasons} if {
    rbac_ok
    not limite_respeitado
    reasons := ["limite_excedido"]
}
```

> ⚠️ Regras com valor (`decisao := ...`) **não podem casar duas vezes com valores diferentes** — o OPA erraria a avaliação ("complete rules must not produce multiple outputs"). Ordene as rules da mais específica para a genérica e garanta exclusividade (note o `not limite_respeitado` na última). O capítulo 4 mostra como testar isso.

O PEP consulta `data.mcp.autorizacao.decisao` e recebe:

```json
{"allow": false, "reasons": ["limite_excedido"]}
```

— que vira a resposta HTTP do MCP (`403` com motivo) **e** o registro de auditoria.

### 3.6 O superpoder: autorizar pelos argumentos

Note o que a seção 3.3 já fez: a decisão considerou `argumentos.valor`. Isso é o que **nenhum scope OAuth faz** — e é o argumento técnico para o projeto OPA da empresa:

- Scope `mcp:faturamento` → *"pode usar ferramentas de faturamento"* (estático, igual para todos);
- OPA → *"a Ana pode emitir reembolso **neste** projeto, **até** R$ 500, **em horário comercial**"* — avaliado **na hora da chamada**, com os argumentos reais que o agente/LLM produziu.

Como agentes encadeiam ferramentas (o risco citado por [p0.dev](https://p0.dev/blog/oauth-scopes-dont-equal-secure-mcp-authorization)), decisões por chamada também dão o gancho para regras de sequência no futuro (ex.: negar `fechar_mes` se houve `emitir_reembolso` < 1h — via dados de contexto enriquecidos pelo PEP).

## 🧪 Laboratório 3 — A política do MCP de faturamento

Construa a política completa (a base é a do curso, em [`exemplos/policies/mcp_autorizacao.rego`](../exemplos/policies/mcp_autorizacao.rego) — tente escrever a sua antes de olhar):

1. `data.json` com: vínculos (ana → financeiro; bruno → engenharia), permissões por papel, limites por ambiente (`{"dev": 100, "prod": 500}`), projetos (`proj-41` → equipe financeiro);
2. `policy.rego` com `decisao` completa: RBAC + limite por valor + dono do projeto (ABAC);
3. **Casos de teste** (todos via `opa eval --format raw 'data.mcp.autorizacao.decisao'`):

| # | input | esperado |
|---|---|---|
| 1 | ana, `listar_faturas`, proj-41 | `{"allow": true, "reasons": []}` |
| 2 | ana, `emitir_reembolso`, valor 600, prod | deny `limite_excedido` |
| 3 | bruno, `listar_faturas` | deny `rbac_negado` |
| 4 | ana, `emitir_reembolso`, valor 450, projeto `proj-99` (outra equipe) | deny `projeto_negado` |
| 5 | token inválido/vencido (se implementou a opção B) | deny `token_invalido` |

4. **Verificação cruzada:** rode cada caso também com a policy de referência do curso — resultados devem bater;
5. **Pergunta de reflexão:** por que o caso 2 é deny mesmo com `allow` de RBAC? (Responda antes de seguir.)

## Próximos passos

- **[Capítulo 4 — OPA como serviço](cap-04-opa-como-servico.md):** a política do laboratório sobe num OPA real com REST API, bundles e decision logs — e ganha testes automatizados com `opa test`;
- Sua política não bateu com algum caso do laboratório? Cole o caso e o resultado para o seu agente revisar — depurar unificação é rápido com uma segunda opinião.

## 📚 Fontes

- [OPA — Authorization Policy (guias oficiais)](https://www.openpolicyagent.org/docs/latest/authorization-policy/)
- [OPA — JWT tokens](https://www.openpolicyagent.org/docs/latest/jwt/)
- [OPA — Input and Output de autorização (tutorial)](https://www.openpolicyagent.org/docs/latest/authorization/)
- [p0.dev — OAuth scopes don't equal secure MCP authorization](https://p0.dev/blog/oauth-scopes-dont-equal-secure-mcp-authorization)
- [Hoop.dev — JWT-based authentication with OPA](https://hoop.dev/blog/jwt-based-authentication-with-open-policy-agent-a-guide-to-secure-and-scalable-authorization)
