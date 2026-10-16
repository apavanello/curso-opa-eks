# Exemplos executáveis — curso OPA para MCPs no EKS

Todos os comandos abaixo foram validados ponta a ponta (OPA v1.21.2, Python 3.12+).

## Estrutura

```
exemplos/
├── policies/mcp_autorizacao.rego        # política de referência (decisão + reasons)
├── policies/mcp_autorizacao_test.rego   # 8 testes (matriz de decisão do cap. 6)
├── data/data.json                       # papéis, projetos, limites por ambiente
├── inputs/tool-call.json                # input de exemplo (reembolso acima do limite)
├── opa-config.yaml                      # config de produção (bundle no S3, SigV4)
├── opa-config-local.yaml                # config de laboratório (bundle via file://)
├── k8s/                                 # manifests: OPA centralizado e MCP+sidecar
└── mcp/                                 # servidor MCP (PEP) + cliente de teste
```

## Laboratório local completo (capítulos 3–4)

```bash
# 1. validação da política (8/8 testes devem passar)
opa test policies data -v

# 2. decisão única via CLI (input PURO — sem o embrulho "input" do curl)
opa eval --data policies --data data/data.json \
  --input inputs/input-reembolso-600.json --format raw \
  'data.mcp.autorizacao.decisao'
# → {"allow":false,"reasons":["limite_excedido"]}

# 3. OPA como serviço (REST API)
opa run --server --addr 127.0.0.1:8181 policies data/data.json &

# 4. consulta via HTTP (aqui SIM embrulhado em {"input": ...})
curl -s -X POST http://127.0.0.1:8181/v1/data/mcp/autorizacao/decisao \
  -H 'Content-Type: application/json' -d @inputs/tool-call.json | jq .result
# → {"allow": false, "reasons": ["limite_excedido"]}
```

## Laboratório ponta a ponta com MCP (capítulo 6)

```bash
# terminal 1 — OPA (PDP)
opa run --server --addr 127.0.0.1:8181 policies data/data.json

# terminal 2 — servidor MCP (PEP)
cd mcp
pip install -r requirements.txt
AMBIENTE=prod uvicorn servidor:app --port 8000

# terminal 3 — matriz de decisão (6 casos: allow, limite, rbac, projeto, admin)
python cliente_teste.py
# TODOS OS CASOS OK

# fail-closed: pare o OPA (Ctrl+C no terminal 1) e repita uma chamada
# → HTTP 503 "autorizacao indisponivel" — nenhuma chamada passa sem decisão
```

## Bundle (capítulos 4–5)

```bash
# estrutura esperada: bundle/policies/*.rego e bundle/data/data.json
mkdir -p bundle && cp -r policies bundle/ && cp -r data bundle/
opa build -b bundle/ -r "v1" -o mcp-bundle.tar.gz

# laboratório com config file://
mkdir -p /tmp/opa-bundles && cp mcp-bundle.tar.gz /tmp/opa-bundles/
opa run --server --config-file=opa-config-local.yaml

# produção: upload para o S3 e use opa-config.yaml (via Secret) — capítulo 5
```
