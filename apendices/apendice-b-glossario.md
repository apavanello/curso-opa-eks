# Apêndice B — Glossário

Os termos como o curso usa (alinhados às [docs do OPA](https://openpolicyagent.org/docs) e à [spec do MCP](https://modelcontextprotocol.io)).

## Autorização (arquitetura)

| Termo | Definição |
|---|---|
| **OPA** | Open Policy Agent — motor de política (PDP) da CNCF; avalia Rego e devolve decisões em JSON |
| **PEP** | Policy *Enforcement* Point — onde a decisão é **aplicada**. No curso: o servidor MCP |
| **PDP** | Policy *Decision* Point — onde a decisão é **calculada**. No curso: o OPA |
| **PIP** | Policy *Information* Point — de onde vêm os **dados** para decidir (papéis, projetos, limites) |
| **Policy as code** | Política escrita em linguagem formal, versionada em Git, testada em CI — não embutida em `if/else` |
| **AuthN / AuthZ** | Autenticação (*quem é você*) / autorização (*o que você pode fazer*) |

## OPA

| Termo | Definição |
|---|---|
| **Rego** | Linguagem declarativa das políticas do OPA (derivada de Datalog). Diz-se "rê-go" |
| **Rego v1** | Sintaxe atual (OPA ≥ 1.0): `allow if { ... }`; a legada omite o `if` |
| **Política** | Arquivos `.rego` — as **regras** de decisão |
| **`input`** | Documento JSON do **caso concreto**, enviado pelo PEP a cada consulta (claims + chamada + contexto) |
| **`data`** | Documento JSON do **universo** — vínculos, papéis, projetos, limites; carregado via bundle |
| **Decisão** | Resposta do OPA — qualquer JSON; convenção do curso: `{"allow": bool, "reasons": [...]}` |
| **Rule** | Declaração Rego que produz um documento virtual quando o corpo casa |
| **Negação por falha** | Semântica do Rego: expressão que não casa deixa a rule **indefinida** (não "falsa") — por isso `default` |
| **`default`** | Valor da rule quando nenhum corpo casa — base do padrão fail-closed (`default allow := false`) |
| **Documento virtual** | Valor calculado por rules, exposto em `data.<package>.<rule>` |
| **Unificação** | Motor de casamento de padrões: variáveis são "resolvidas" para tornar expressões verdadeiras |
| **Comprehension** | Construção de coleção por iteração: `[x \| some x in ...]` (array), `{x \| ...}` (set), `{k: v \| ...}` (object) |
| **`with ... as`** | Reescreve `input`/`data`/built-ins num escopo — usado em testes e mocks |

## Distribuição e operação

| Termo | Definição |
|---|---|
| **Bundle** | `.tar.gz` com políticas + dados, servido por HTTP/S3; o OPA baixa e troca atomicamente |
| **Revision** | Rótulo de versão gravado no bundle (`opa build -r`); aparece em cada decision log |
| **`config.yaml`** | Configuração do processo OPA (bundles, services, decision logs, status) — via Secret no K8s |
| **Decision log** | Registro JSON de cada decisão (input, resultado, revision, timestamp) — a auditoria |
| **`/v1/data/...`** | Endpoint REST de consulta: `POST` com `{"input": ...}` → `{"result": ...}` |
| **`/health/live`, `/health/ready`** | Probes do OPA (ready inclui estado do bundle) |
| **Fail-closed** | PDP fora do ar → PEP **nega tudo** (posição padrão do curso) |
| **Fail-open** | PDP fora do ar → PEP deixa passar (exceção consciente, por ferramenta, auditada) |
| **opa-envoy / ext_authz** | Plugin que faz o OPA atender a API de autorização externa do Envoy (enforcement no gateway) |
| **Assinatura de bundle** | Assinar no build e verificar no OPA — só políticas assinadas são ativadas |

## Identidade e MCP

| Termo | Definição |
|---|---|
| **MCP** | Model Context Protocol — protocolo aberto que conecta clientes de IA a **servidores MCP** que expõem tools/resources/prompts |
| **Tool** | Função que o modelo invoca **com argumentos** — a unidade que o curso autoriza |
| **Streamable HTTP** | Transporte do MCP para rede (o usado em clusters); o outro é stdio |
| **OAuth 2.1** | Base da spec de autorização do MCP: o servidor MCP é um resource server; clientes usam bearer tokens |
| **Scope** | Autorização **grossa** no token (*este token cobre ferramentas de faturamento*) — não substitui AuthZ fina |
| **JWT** | JSON Web Token — carrega claims (`sub`, `scope`, `equipe`…); validado no AuthN, consultado no AuthZ |
| **JWKS** | JSON Web Key Set — conjunto de chaves públicas do emissor; pode ser distribuído ao OPA via bundle |
| **RBAC** | Autorização por papéis (papel → permissões) |
| **ABAC** | Autorização por atributos (equipe, projeto, valor, ambiente, horário) |
| **EKS Pod Identity** | Mecanismo da AWS para dar credenciais IAM a pods (usado para o OPA ler bundles do S3) |
| **SigV4** | Esquema de assinatura de requisições AWS — o plugin de bundle do OPA fala nativamente |
