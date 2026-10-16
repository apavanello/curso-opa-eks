# Capítulo 7 — Operação: política é produto

> O desenho funciona no laboratório; agora ele precisa sobreviver à segunda-feira. Este capítulo cobre o ciclo de vida operacional das políticas: **CI de políticas** (a esteira completa), **observabilidade** (métricas Prometheus + decision logs no CloudWatch), a decisão arquitetural **fail-open × fail-closed**, e governança — quem pode mudar o que, com que revisão, com que rollback.

## 🎯 Objetivos

- Montar o **pipeline de CI de políticas** (PR → testes → build → S3 → rollout);
- Instrumentar o OPA: **métricas Prometheus** e **decision logs** como fonte de auditoria;
- Decidir **fail-open × fail-closed** por componente — com critérios, não por medo;
- Praticar **rollback de política** (é diferente de rollback de aplicação);
- Aplicar o **checklist de produção** para a frota OPA + MCPs.

## 📖 Conteúdo

### 7.1 O pipeline de políticas

Política é código com **deploy contínuo**: um bundle novo atinge todos os OPAs em minutos, sem aprovação de janela de mudança **se você não construir governança**. O pipeline mínimo (GitHub Actions; traduz para seu CI):

```yaml
# .github/workflows/policy-ci.yml
name: policy-ci
on: { pull_request: { paths: ["policies/**", "data/**"] } }
jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: open-policy-agent/setup-opa@v2
        with: { opa-version: latest }
      - run: opa fmt --fail policies/            # 1. formatação canônica
      - run: opa check --strict policies/        # 2. lint
      - run: opa test policies data -v           # 3. testes (a matriz do cap. 6!)
  release:
    if: github.ref == 'refs/heads/main'
    needs: validate
    runs-on: ubuntu-latest
    permissions: { id-token: write, contents: read }   # OIDC → AWS
    steps:
      - uses: actions/checkout@v4
      - uses: open-policy-agent/setup-opa@v2
        with: { opa-version: latest }
      - run: opa build -b bundle/ -r "${{ github.sha }}" -o mcp-bundle.tar.gz
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/gha-opa-bundle-publisher
          aws-region: us-east-1
      - run: aws s3 cp mcp-bundle.tar.gz s3://empresa-opa-bundles/mcp/bundle.tar.gz
```

Regras de governança que o pipeline codifica:

1. **Ninguém publica bundle sem PR** — o S3 é gravado só pelo CI (a política IAM do Pod Identity é leitura; a de publicação é só do role do CI);
2. **Revision = commit SHA** — cada decision log identifica a política exata (auditoria e rollback);
3. **Rollback = reverter o PR e re-rodar o pipeline** (ou republicar o bundle anterior). Como o OPA troca o bundle inteiro atomicamente, voltar é seguro e rápido — **sem redeploy**;
4. **Assinatura de bundle** em produção: assine no build (`opa build --signing-key`) e configure verificação no OPA — impede que alguém com acesso ao S3 injete política maliciosa ([docs — bundle signing](https://www.openpolicyagent.org/docs/management-bundles/#signing)).

### 7.2 Observabilidade

**Métricas Prometheus** — o OPA expõe `/metrics` ([docs — monitoring](https://www.openpolicyagent.org/docs/monitoring)); as que importam para a missão:

| Métrica | O que revela |
|---|---|
| `http_server_request_duration_seconds` (p50/p99) | Latência de decisão — o budget do PEP (timeout!) |
| `bundle_loaded_counter` / `bundle_request_duration_seconds` | Health do refresh de política |
| `http_server_requests_total` por código | Volume de decisões; erros 5xx do próprio OPA |
| `decision_logs_*` (se buffer) | Entupimento do envio de logs |

ServiceMonitor/Padrão Prometheus no EKS: o mesmo `prometheus-operator` que você já conhece raspa `opa:8181/metrics`. Alarmes sugeridos: p99 de decisão > 100ms; bundle sem load > 30min; 5xx no OPA.

**Decision logs** — já habilitados via `console: true` (stdout → CloudWatch). Consultas que valem dashboards:

```awk
# CloudWatch Logs Insights — negações por motivo, últimas 24h
fields @timestamp, input.claims.sub, input.chamada.ferramenta, result.reasons[0] as motivo
| filter result.allow == false
| stats count() by motivo, input.chamada.ferramenta
| sort count() desc
```

> 💡 **Negações são produto:** um pico de `rbac_negado` numa ferramenta nova normalmente significa "política desatualizada da realidade do time", não "ataque". Consumir esses dados fecha o ciclo de melhoria das políticas.

### 7.3 Fail-open × fail-closed (a decisão arquitetural)

O que acontece quando o OPA **não responde**? Duas filosofias ([docs — kubernetes deployment, seção hardening](https://openpolicyagent.org/docs/deploy/k8s)):

| | **Fail-closed** (nada passa) | **Fail-open** (tudo passa) |
|---|---|---|
| OPA fora do ar | Todas as ferramentas MCP retornam erro de autorização | As chamadas seguem sem decisão |
| Custo | Indisponibilidade **da ferramenta** | Janela de **acesso sem controle** |
| Adequado para | Ferramentas de escrita/dados sensíveis, compliance (PCI, LGPD) | Ferramentas só-leitura de baixo impacto |

**A posição deste curso** (e a prática comum em authorization): **fail-closed por padrão**, com exceções conscientes. No PEP do capítulo 6 o `except httpx.HTTPError` já implementa isso. Se uma ferramenta só-leitura for crítica demais para cair, trate **por ferramenta**, nunca globalmente:

```python
PESSIMISTA = {"emitir_reembolso", "fechar_mes"}      # fail-closed
OTIMISTA   = {"listar_faturas"}                       # fail-open consciente

def autorizar(...):
    try:
        ...  # consulta OPA
    except httpx.HTTPError:
        if ferramenta in PESSIMISTA:
            raise PermissionError("opa_indisponivel")   # fecha
        # log MUITO alto e alerta antes de abrir:
        logger.critical("fail-open", extra={...})
        return {"allow": True, "reasons": ["fail_open_auditado"]}
```

E lembre: fail-closed exige a **disponibilidade do OPA** como requisito — daí réplicas + HPA + anti-afinidade do capítulo 5.

### 7.4 Versionamento e ambientes

- **Um repo de políticas por domínio** (ex.: `policies-faturamento`), ou monorepo com bundle por MCP — mas **bundle por MCP** (root/manifest separado) sempre: política de faturamento não deve cascatear no MCP de RH;
- **Ambientes**: `dev` e `prod` são **dados diferentes** (limites, projetos) e podem ser políticas iguais — os limites por ambiente do curso já mostram o padrão (`data.limites[ambiente]`). Bundes distintos `mcp-dev/bundle.tar.gz` e `mcp-prod/bundle.tar.gz`, mesma policy, data diferente;
- **Promotion:** PR em branch `dev` publica bundle dev; merge para `main` publica prod. A matriz de testes roda em **ambos os conjuntos de dados**.

### 7.5 Checklist de produção

**Política**
- [ ] Toda rule `allow` exige conditions nomeadas (RBAC + ABAC), `default` nega;
- [ ] `decisao` com `reasons` — sem motivo genérico "negado";
- [ ] Matriz de decisão coberta por `opa test` (o CI bloqueia sem teste novo para rule nova);
- [ ] Bundle assinado e verificado no OPA.

**Infra (EKS)**
- [ ] Réplicas ≥ 3 (se centralizado), HPA, anti-afinidade, QoS Guaranteed;
- [ ] OPA nunca exposto fora do cluster; NetworkPolicy fechando namespaces;
- [ ] Pod Identity com política IAM mínima (leitura do prefixo do bundle);
- [ ] Readiness inclui bundle carregado (senão o pod "pronto" decide com política vazia — no sidecar, `--addr=127.0.0.1`).

**Operação**
- [ ] Alarmes: p99 de decisão, bundle stale, erros 5xx do OPA, taxa de fail-open;
- [ ] Runbook: "decisão errada em prod" = revert PR + republicar bundle anterior (≤5min);
- [ ] Revisão trimestral de `data` (papel de quem saiu da empresa ainda vincula?);
- [ ] Auditoria consegue responder: "por que a chamada X foi negada terça passada?" com decision log + revision.

## 🧪 Laboratório 7 — O pipeline completo

1. Crie um repo com `bundle/` (policies + data + testes) e o workflow da seção 7.1 (adapte bucket/role);
2. Abra um PR que **quebra** um teste (mude um limite esperado) → CI deve bloquear;
3. Corrija, faça merge → bundle publicado; confira o rollout no pod (revision nova no log do OPA);
4. **Rollback:** reverta o merge → bundle anterior volta; meça o tempo total (meta: <5min);
5. No CloudWatch Insights, rode a query de negações da seção 7.2 contra os logs do laboratório 6;
6. **Simule falha:** escale o OPA centralizado para 0 réplicas e comprove o comportamento fail-closed do MCP (lab 6, passo 4) — e o alarme que faltaria no seu setup.

## Fechamento do curso

Você saiu do "o que é OPA" até uma plataforma de autorização para MCPs no EKS: Rego, decisão por ferramenta com argumentos, bundles versionados no S3, PEP fail-closed, auditoria e pipeline. A trilha natural de continuação:

- Implementar o PEP na stack real da empresa (o agente traduz o `autorizar()` para Go/Node/Java);
- [opa-envoy-plugin](https://github.com/open-policy-agent/opa-envoy-plugin) se os MCPs passarem a ter gateway comum;
- Partial evaluation e data filtering quando as políticas começarem a filtrar *conjuntos* de dados (ex.: "mostre só os projetos dela") — tópico avançado das [docs](https://www.openpolicyagent.org/docs/latest/policy-performance/).

## 📚 Fontes

- [OPA — Monitoring](https://www.openpolicyagent.org/docs/monitoring)
- [OPA — Management Bundles (assinatura)](https://www.openpolicyagent.org/docs/management-bundles/)
- [OPA — CI de políticas (GitHub Actions + setup-opa)](https://github.com/open-policy-agent/setup-opa)
- [OPA — Kubernetes Deployment (hardening)](https://openpolicyagent.org/docs/deploy/k8s)
- [Styra — boas práticas de política em produção (blog da empresa criadora do OPA)](https://styra.com/blog/)
