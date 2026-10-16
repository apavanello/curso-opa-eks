# Capítulo 4 — OPA como serviço

> Sua política de autorização funciona com `opa eval` — hora de servi-la. Neste capítulo o OPA vira um **processo de longa duração** com REST API, a política e os dados passam a chegar via **bundles**, cada decisão passa a ser **registrada** (decision logs), e a política ganha **testes automatizados** com `opa test`. É o degrau entre o laboratório local e o deploy no EKS do capítulo 5.

## 🎯 Objetivos

- Rodar o OPA em modo servidor e consultar a **REST API `/v1/data`** com `curl`;
- Entender **bundles**: empacotar política + dados e distribuir com versionamento;
- Escrever o **`config.yaml`** do OPA (bundles, decision logs, diagnóstico);
- Habilitar e ler **decision logs** — a auditoria das decisões;
- Escrever **testes de política** com `opa test` (TDD de Rego);
- Conhecer `opa check` e o pipeline local completo: `fmt → check → test`.

## 📖 Conteúdo

### 4.1 Modo servidor e a REST API

O binário `opa` vira serviço com `run --server` ([docs — REST API](https://openpolicyagent.org/docs/rest-api)):

```bash
# do diretório do laboratório 3:
opa run --server ./policies ./data.json
# por padrão escuta em http://localhost:8181
```

O PEP (seu servidor MCP) consulta o documento virtual da política:

```bash
curl -s -X POST http://localhost:8181/v1/data/mcp/autorizacao/decisao \
  -H 'Content-Type: application/json' \
  -d @exemplos/inputs/tool-call.json | jq '.result'
```

```json
{
  "allow": false,
  "reasons": ["limite_excedido"]
}
```

Anatomia da chamada:

| Peça | O que é |
|---|---|
| `POST /v1/data/<caminho>` | Avalia o documento virtual `data.mcp.autorizacao.decisao` |
| `{"input": {...}}` | O corpo da requisição **embrulha** o input: `{"input": <seu input>}` |
| `result` | A decisão; **ausente** se o documento for indefinido (sem `default`) |
| `GET /health/live`, `/health/live` | Probes de liveness/readiness (usadas no deploy no cap. 5) |

> 💡 **Convenção de mercado:** em vez de `GET`, sempre `POST` com `input` no corpo — é o formato que gateways e SDKs usam. O input do arquivo `tool-call.json` precisa estar dentro da chave `"input"`.

> ⚠️ **Pegadinha que derruba todo mundo:** `opa eval --input arquivo.json` espera o input **puro**; o `curl` para `/v1/data` espera o **mesmo JSON embrulhado** em `{"input": ...}`. Por isso o repositório traz os dois arquivos (`inputs/input-reembolso-600.json` para eval, `inputs/tool-call.json` para curl).

Outros endpoints úteis: `/v1/policies` (políticas carregadas), `/v1/data` (árvore `data` inteira — ótimo para depurar), `/metrics` (Prometheus — capítulo 7).

### 4.2 Bundles: política e dados versionados

Manter 20 pods de OPA com `opa run ./policies` não escala — política atualizada exige redeploy. O mecanismo nativo é o **bundle** ([docs — bundles](https://www.openpolicyagent.org/docs/management-bundles/)): um `.tar.gz` com políticas e dados que o OPA **baixa e recarrega sozinho**, com polling configurável.

Estrutura de um bundle:

```
bundle/
├── bundle/.manifest        # opcional: raízes do bundle (namespacing)
├── policies/
│   └── mcp_autorizacao.rego
└── data/
    └── data.json           # papéis, limites, projetos...
```

```bash
# empacotar (o diretório bundle/ é a raiz)
opa build -b bundle/ -o mcp-bundle.tar.gz
# o tar.gz gerado já contém o manifest — versione-o no S3/Git
```

Por que bundles (e não redeploy):

- **Atualização sem redeploy** — a política muda de hora em hora se precisar, sem tocar nos pods;
- **Atômico** — o OPA troca política+dados de uma vez; nunca fica com metade de cada versão;
- **Versionado** — o bundle é um artefato de CI (capítulo 7): PR → testes → build → S3;
- **Verificável** — o OPA só ativa bundles assinados, se você configurar assinatura (recomendado em produção — docs *bundle signing*).

### 4.3 O `config.yaml`

Toda a configuração do OPA em produção vive num YAML ([docs — configuration](https://www.openpolicyagent.org/docs/configuration.html)). O do curso (versão completa em [`exemplos/opa-config.yaml`](../exemplos/opa-config.yaml)):

```yaml
# opa-config.yaml
bundles:
  mcp:
    service: bundle-service            # referência ao bloco services abaixo
    poll:
      min_delay_seconds: 30            # polling: nova política em ≤ ~1min
      max_delay_seconds: 120

services:
  bundle-service:
    url: https://bundles.empresa.com    # S3/CloudFront/API interna servindo o tar.gz

decision_logs:
  console: true                        # primeiro passo: logs no stdout

# em produção, proteja a API do OPA (o PEP é in-cluster):
# authentication / tls / etc — ver docs e capítulo 5
```

Rodando com configuração:

```bash
opa run --server --config-file=opa-config.yaml --addr 127.0.0.1:8181
```

Blocos que importam para a missão:

| Bloco | Papel | No EKS (cap. 5) |
|---|---|---|
| `bundles` | De onde e com que frequência baixar política+dados | tar.gz no **S3** via Pod Identity |
| `services` | "Servidores" de bundle (URL + credenciais) | S3 com assinatura SigV4 ou endpoint interno |
| `decision_logs` | Registrar toda decisão (input, resultado, política ativa) | stdout → **CloudWatch** |
| `status` | Reportar estado (bundle ativo, erros) para um endpoint | painel de saúde da frota OPA |

### 4.4 Decision logs: a auditoria

Com `decision_logs.console: true`, toda consulta gera um registro JSON no stdout ([docs — decision logs](https://www.openpolicyagent.org/docs/management-decision-logs/)):

```json
{
  "decision_id": "4d2f...",
  "input": { "chamada": { "ferramenta": "emitir_reembolso", "argumentos": { "valor": 600 } }, ... },
  "labels": { "id": "opa-7d9c...", "version": "1.x.x" },
  "result": { "allow": false, "reasons": ["limite_excedido"] },
  "path": "mcp/autorizacao/decisao",
  "timestamp": "2026-10-16T14:30:01Z",
  "bundle": { "revision": "v42" }
}
```

É o artefato que o time de segurança quer: **quem tentou o quê, quando, com qual versão da política, e por que foi negado**. No EKS, stdout vira CloudWatch Logs automaticamente (capítulo 5). Em escala, o destino costuma ser Kinesis/Firehose → S3/Athena — a API de decision logs do OPA também aceita *upload* em lote para um endpoint HTTP.

### 4.5 `opa test`: TDD de políticas

Regra de ouro: **política sem teste é bug em produção com deploy instantâneo**. Rego tem testes nativos ([docs — policy testing](https://www.openpolicyagent.org/docs/policy-testing/)):

```rego
// mcp_autorizacao_test.rego — mesma pasta da policy
package mcp.autorizacao_test

import rego.v1

import data.mcp.autorizacao

# convenção: prefixo test_
test_ana_pode_listar_faturas if {
    autorizacao.decisao with input as {
        "claims": {"sub": "ana@empresa.com"},
        "chamada": {"ferramenta": "listar_faturas", "argumentos": {"projeto_id": "proj-41"}},
        "contexto": {"ambiente": "prod"}
    } == {"allow": true, "reasons": []}
}

test_reembolso_acima_do_limite_negado if {
    decisao := autorizacao.decisao with input as {
        "claims": {"sub": "ana@empresa.com"},
        "chamada": {
            "ferramenta": "emitir_reembolso",
            "argumentos": {"projeto_id": "proj-41", "valor": 600}
        },
        "contexto": {"ambiente": "prod"}
    }
    decisao.allow == false
    decisao.reasons == ["limite_excedido"]
}
```

Execução:

```bash
opa test policies data -v
# PASS: 8/8
```

O operador essencial é o **`with ... as ...`** — reescreve `input` (ou `data`, ou funções built-in!) para o escopo daquele teste. Note que ele também permite **mockar built-ins** (`with io.jwt.verify_rs256 as ...`) — decisivo para testar caminhos de JWT sem chaves reais.

### 4.6 O pipeline local completo

Antes de qualquer commit de política, rode:

```bash
opa fmt --fail policies data        # 1. formatação canônica (falha se mudar algo)
opa check --strict policies         # 2. análise estática (variáveis não usadas, etc.)
opa test policies data -v           # 3. testes (política E dados)
opa build -b bundle/ -o /tmp/mcp-bundle.tar.gz   # 4. build local do bundle
```

Esse quadrinho vira o CI do capítulo 7 — política é código e merece o mesmo rigor do Terraform (`fmt/validate/plan`).

## 🧪 Laboratório 4 — Servindo a política do laboratório 3

1. Estruture o bundle do laboratório 3 (`policies/` + `data/data.json`) e rode `opa build`;
2. Suba o OPA apontando para um bundle **local** (sem S3 ainda):

   ```yaml
   # config-local.yaml
   bundles:
     mcp:
       service: local
       poll: { min_delay_seconds: 5, max_delay_seconds: 10 }
   services:
     local:
       url: file:///absoluto/para/pasta/do/bundle   # OPA busca mcp-bundle.tar.gz
   decision_logs:
     console: true
   ```

3. Consulte a decisão com `curl` (lembre do embrulho `{"input": ...}`) e confira o **decision log** gerado no stdout do OPA;
4. **Teste o refresh quente:** mude um limite no `data.json`, rebuild o bundle, espere ~10s e refaça a mesma chamada — a decisão muda **sem reiniciar** o OPA;
5. Copie os dois testes da seção 4.5, adicione o caso 3 do laboratório 3 (bruno, `rbac_negado`) e rode `opa test`;
6. **Verificação:** `curl .../v1/data/mcp/autorizacao/decisao` com o input do caso 2 do laboratório 3 deve responder `{"allow": false, "reasons": ["limite_excedido"]}` — e o decision log correspondente deve aparecer no stdout.

## Próximos passos

- **[Capítulo 5 — Deploy no EKS](cap-05-deploy-eks.md):** o OPA de laboratório vira Deployment (ou sidecar) no EKS, buscando bundles do S3 com EKS Pod Identity;
- Erros estranhos no `with` ou no bundle? Mande para o agente — `opa test` falhando com "complete rules must not produce multiple outputs" tem causa conhecida (seção 3.5).

## 📚 Fontes

- [OPA — REST API Reference](https://openpolicyagent.org/docs/rest-api)
- [OPA — Management: Bundles](https://www.openpolicyagent.org/docs/management-bundles/)
- [OPA — Management: Decision Logs](https://www.openpolicyagent.org/docs/management-decision-logs/)
- [OPA — Policy Testing](https://www.openpolicyagent.org/docs/policy-testing/)
- [OPA — Configuration Reference](https://www.openpolicyagent.org/docs/configuration.html)
- [OPA — Deploy no Kubernetes](https://openpolicyagent.org/docs/deploy/k8s)
