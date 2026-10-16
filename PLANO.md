# Plano do curso — OPA para autorização de MCPs no EKS

## Missão (o porquê)

A empresa está construindo **servidores MCP** que se conectam a sistemas internos no **EKS via API**. Para não espalhar regras `if/else` de permissão no código de cada MCP, e para ter governança central sobre *quem pode chamar o quê*, a camada de **autenticação e autorização** será feita com **OPA**:

- **Autenticação** — validação do token (OAuth 2.1/JWT) que o cliente MCP apresenta;
- **Autorização** — decisão por **chamada de ferramenta**: identidade + papel + contexto + argumentos da ferramenta → `allow`/`deny`.

Tudo que o curso ensina é ancorado nessa missão. Nada de política de Kubernetes admission control (Gatekeeper) — não é o foco aqui.

## Divisão de responsabilidades (o insight central)

| Camada | Tecnologia | Responde |
|---|---|---|
| Autenticação (AuthN) | OAuth 2.1 / JWT (spec do MCP) + validação no OPA | *Quem é você?* |
| Autorização grossa | Scopes do token | *Qual domínio de ferramentas você pode tocar?* |
| **Autorização fina** | **OPA/Rego** | *Este usuário, esta ferramenta, estes argumentos, agora — pode?* |

Fonte-chave: [OAuth scopes don't equal secure MCP authorization (p0.dev)](https://p0.dev/blog/oauth-scopes-dont-equal-secure-mcp-authorization) e [spec de autorização do MCP](https://modelcontextprotocol.io/docs/2026-07-28/tutorials/security/authorization).

## Trilha e progressão pedagógica

Cada capítulo entrega uma habilidade usada no próximo (zona de desenvolvimento proximal):

1. **OPA em si** (conceitual) — entender o modelo decisão = política + dados + entrada, e onde o OPA entra na arquitetura MCP/EKS. *Sem código.*
2. **Rego** (linguagem) — escrever regras, entender negação por falha, terminar toda política em `default deny := false`. *Laboratório local com `opa eval`.*
3. **Rego para autorização** (aplicado) — o formato do `input` de uma chamada de API/ferramenta, decodificar/validar JWT, RBAC + ABAC, autorizar pelos **argumentos** da ferramenta. *Habilidade central da missão.*
4. **OPA como serviço** (integração) — REST API `/v1/data`, bundles, decision logs, `opa test`. *O MCP passa a consultar o OPA via HTTP.*
5. **Deploy no EKS** (infraestrutura) — sidecar vs. serviço centralizado, bundles no S3 via Pod Identity, probes/HPA. *Conecta com o curso-eks-argocd.*
6. **Projeto final** (síntese) — MCP de faturamento: OAuth 2.1 + OPA por ferramenta, ponta a ponta no EKS.
7. **Operação** (produção) — CI de políticas, observabilidade, fail-open vs. fail-closed, governança.

## Formato

- Markdown, como os cursos anteriores do aluno ([curso-eks-argocd](../curso-eks-argocd/), [curso-terraform](../curso-terraform/));
- Capítulos com: intro conectada ao anterior → 🎯 objetivos → 📖 conteúdo (seções numeradas, tabelas, diagramas mermaid, códigos completos) → 🧪 laboratório com verificação → próximos passos;
- Exemplos completos e executáveis em `exemplos/`;
- Sintaxe **Rego v1** (`allow if { ... }`) — a atual desde o OPA 1.0; sintaxe legada (`allow { }`) citada quando relevante para ler materiais antigos.

## Perfil do aluno

- Já domina EKS (ALB, Karpenter, Pod Identity, ArgoCD) e Terraform;
- Trabalha com a plataforma onde os MCPs serão construídos;
- Prefere conteúdo técnico direto, tabelas de decisão e laboratórios verificáveis.

## Regras do professor (agente)

- Ancorar cada conceito na missão MCP/EKS;
- Citar fontes primárias (docs do OPA, spec do MCP) para toda afirmação normativa;
- Corrigir políticas Rego do aluno quando ele pedir revisão;
- Sugerir próximo capítulo com base no último concluído.
