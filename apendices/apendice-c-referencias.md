# Apêndice C — Referências

Fontes por tema, priorizando documentação oficial. Todas foram usadas na construção deste curso (out/2026).

## OPA — documentação oficial

- [OPA — Documentação](https://www.openpolicyagent.org/docs/latest/) — comece por aqui
- [Policy Language (Rego)](https://openpolicyagent.org/docs/policy-language) — a linguagem
- [Policy cheat sheet (PDF)](https://www.openpolicyagent.org/docs/latest/policy-cheat-sheet/)
- [REST API Reference](https://openpolicyagent.org/docs/rest-api)
- [Integrating OPA](https://openpolicyagent.org/docs/integration) — REST, Go library, sidecar
- [Authorization (tutorial de input/output)](https://www.openpolicyagent.org/docs/latest/authorization/)
- [Authorization Policy (guias)](https://www.openpolicyagent.org/docs/latest/authorization-policy/)
- [JWT](https://www.openpolicyagent.org/docs/latest/jwt/)
- [Deploy no Kubernetes (padrões)](https://openpolicyagent.org/docs/deploy/k8s)
- [Management: Bundles](https://www.openpolicyagent.org/docs/management-bundles/) — inclui assinatura
- [Management: Decision Logs](https://www.openpolicyagent.org/docs/management-decision-logs/)
- [Configuration Reference](https://www.openpolicyagent.org/docs/configuration.html) — bundles S3/SigV4, TLS, auth
- [Policy Testing](https://www.openpolicyagent.org/docs/policy-testing/)
- [Monitoring](https://www.openpolicyagent.org/docs/monitoring)
- [opa-envoy-plugin (GitHub)](https://github.com/open-policy-agent/opa-envoy-plugin) — ext_authz
- [setup-opa (GitHub Action)](https://github.com/open-policy-agent/setup-opa)

## MCP — spec e segurança

- [Model Context Protocol — site e spec](https://modelcontextprotocol.io)
- [MCP — Authorization (tutorial oficial de segurança)](https://modelcontextprotocol.io/docs/2026-07-28/tutorials/security/authorization)
- [Red Hat — MCP Security: Authentication & Authorization](https://www.redhat.com/en/blog/mcp-security-implementing-robust-authentication-and-authorization)
- [Solo.io — MCP Authorization is a Non-Starter for Enterprise](https://www.solo.io/blog/mcp-authorization-is-a-non-starter-for-enterprise)
- [p0.dev — OAuth scopes don't equal secure MCP authorization](https://p0.dev/blog/oauth-scopes-dont-equal-secure-mcp-authorization) — o argumento da AuthZ fina
- [Aembit — MCP OAuth 2.1, PKCE, and Agent Identity](https://aembit.io/blog/mcp-oauth-2-1-pkce-and-the-future-of-ai-authorization)
- [Permit.io — OAuth on MCP Implementation Guide](https://www.permit.io/blog/oauth-on-mcp)
- [TrueFoundry — MCP AuthN vs AuthZ](https://www.truefoundry.com/blog/mcp-authentication-and-authorization)

## Tutoriais de Rego e autorização com OPA

- [Spacelift — Open Policy Agent Rego Tutorial](https://spacelift.io/blog/open-policy-agent-rego)
- [Snyk — Rego 101](https://snyk.io/blog/introduction-to-rego)
- [InfraCloud — Microservices authorization with OPA](https://www.infracloud.io/blogs/opa-microservices-authorization-simplified)
- [Kong — How to Manage Your API Policies with OPA](https://konghq.com/blog/engineering/how-to-manage-your-api-policies-with-opa-open-policy-agent)
- [Hoop.dev — JWT-based authentication with OPA](https://hoop.dev/blog/jwt-based-authentication-with-open-policy-agent-a-guide-to-secure-and-scalable-authorization)
- [Oso — 5 OPA examples and use cases](https://www.osohq.com/learn/open-policy-agent-examples-and-use-cases)
- [Styra (criadores do OPA) — blog](https://styra.com/blog/)

## AWS / EKS

- [AWS — EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
- [AWS Blog — OPA as a sidecar (ECS/Fargate, padrões válidos para EKS)](https://aws.amazon.com/blogs/containers/)
- Recomendação do autor: um curso anterior de EKS/ArgoCD (ALB, Karpenter, Pod Identity, ArgoCD) e outro de Terraform como base prévia

## Comunidade (para tirar dúvidas com praticantes)

- [OpenPolicyAgent Slack](https://openpolicyagent.org/community/) — canal `#opa`, `#rego`
- [Stack Overflow — tags `open-policy-agent` + `rego`](https://stackoverflow.com/questions/tagged/open-policy-agent)
- [GitHub do OPA — discussions/issues](https://github.com/open-policy-agent/opa)
- [r/kubernetes](https://www.reddit.com/r/kubernetes/) — threads recorrentes sobre Rego/OPA

> 💡 Ao perguntar na comunidade, inclua: versão do OPA (`opa version`), a policy, o `input` e a query — respostas chegam muito mais rápido.
