# Curso: OPA (Open Policy Agent) para Autorização de MCPs no EKS

> **Missão:** a empresa está construindo **MCPs** (Model Context Protocol) que se conectam a sistemas no EKS via API, e usará o **OPA como camada de autenticação e autorização**. Este curso ensina Rego e o OPA exatamente para esse objetivo: políticas de decisão por requisição/ferramenta, servidas a partir do EKS.

## Por que este curso existe

A especificação do MCP adota **OAuth 2.1** para autenticação — ela responde *"quem é o cliente"*. Mas **scopes de token não bastam** para autorização: tokens são estáticos (congelam permissões até expirar), não conhecem contexto (*qual projeto? qual recurso? a que horas?*) e não distinguem dois usuários com o mesmo scope. A prática recomendada para MCPs enterprise é uma camada de **autorização fina por chamada de ferramenta**, avaliada no momento do request — que é exatamente o papel do OPA como *Policy Decision Point* (PDP).

Este curso cobre o caminho completo:

1. **Rego do zero** até políticas de autorização de API com JWT;
2. **OPA como serviço** (REST API, bundles, decision logs);
3. **Deploy no EKS** (sidecar vs. serviço centralizado);
4. **Projeto final**: um MCP de faturamento onde cada chamada de ferramenta passa por decisão OPA (papel + projeto + argumentos da ferramenta).

## Estrutura

| Seção | Conteúdo |
|---|---|
| [Capítulo 1](capitulos/cap-01-opa-fundamentos.md) | OPA: o que é, PEP/PDP, o modelo de decisão — e por que MCPs precisam dele |
| [Capítulo 2](capitulos/cap-02-rego-fundamentos.md) | Rego do zero: packages, rules, negação por falha, `default deny` |
| [Capítulo 3](capitulos/cap-03-rego-autorizacao.md) | Rego para autorização: input, JWT, RBAC/ABAC, decisões por ferramenta |
| [Capítulo 4](capitulos/cap-04-opa-como-servico.md) | OPA como serviço: REST API, bundles, decision logs, `opa test` |
| [Capítulo 5](capitulos/cap-05-deploy-eks.md) | Deploy no EKS: sidecar vs. cluster service, S3 + Pod Identity, hardening |
| [Capítulo 6](capitulos/cap-06-projeto-mcp-opa.md) | Projeto final: MCP + OAuth 2.1 + OPA no EKS, ponta a ponta |
| [Capítulo 7](capitulos/cap-07-operacao.md) | Operação: CI de políticas, observabilidade, fail-open vs. fail-closed |
| [Capítulo 8](capitulos/cap-08-opa-bancos-de-dados.md) | Bancos de dados: DocumentDB e Valkey, data filtering (Compile API) |
| [Capítulo 9](capitulos/cap-09-modos-de-deploy.md) | Modos de deploy: sidecar, DaemonSet, opa-envoy, library Go, WASM, Gatekeeper |
| [Capítulo 10](capitulos/cap-10-cookbook.md) | Cookbook: 6 receitas de política testadas (step-up, janela, quota, PII, agentes, break-glass) |
| [Apêndice A](apendices/apendice-a-cheatsheet-rego.md) | Cheatsheet de Rego para consulta rápida |
| [Apêndice B](apendices/apendice-b-glossario.md) | Glossário: PEP, PDP, bundle, decision, MCP, JWT… |
| [Apêndice C](apendices/apendice-c-referencias.md) | Referências e fontes de alta confiança |

## Pré-requisitos

- **Kubernetes/EKS** — namespaces, Deployments, Services, IRSA/EKS Pod Identity (pré-requisito: um curso anterior de EKS/ArgoCD ou equivalente);
- **Linha de comando** — `curl`, `jq`, `kubectl`;
- Um cluster EKS de laboratório ajuda, mas os capítulos 1–4 rodam **100% local** com o binário `opa`.

## Como usar

- Capítulos **1–4**: laboratório local (só o binário `opa`);
- Capítulos **5–6**: laboratório no EKS;
- Cada capítulo tem objetivos, conteúdo, diagrama e **laboratório prático** com verificação;
- Os arquivos de política e manifests prontos estão em [`exemplos/`](exemplos/);
- Travou em algo? **Pergunte ao seu agente** — ele é o professor deste curso e pode explicar, corrigir suas políticas e revisar seus laboratórios.

## Ferramentas usadas

| Ferramenta | Uso | Instalação |
|---|---|---|
| `opa` | Avaliar/testes/servir políticas | `brew install opa` ou [release oficial](https://github.com/open-policy-agent/opa/releases) |
| `curl` + `jq` | Chamar a API do OPA | já presente na maioria dos sistemas |
| `kubectl` | Laboratórios EKS | curso anterior |
| `docker` (opcional) | Rodar OPA containerizado | — |
