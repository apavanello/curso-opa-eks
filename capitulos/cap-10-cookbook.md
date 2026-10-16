# Capítulo 10 — Cookbook: casos reais, políticas prontas

> Um capítulo para **consultar e copiar**: seis receitas de política que aparecem em quase toda plataforma de MCPs — cada uma com o cenário, a regra de negócio, a política inteira, o input, a decisão e o comando para reproduzir. Todas validadas com OPA 1.21 (23/23 testes no repositório). As receitas são **módulos independentes** ([`exemplos/policies/cookbook/`](../exemplos/policies/cookbook/)) — você compõe as que precisar.

## 🎯 Objetivos

- Ter um repertório de políticas prontas para os casos que a empresa vai esbarrar;
- Ver, em cada receita, como uma regra de negócio vira Rego (e onde ficam os dados × a política);
- Aprender a **compor receitas** num único fluxo de decisão.

## 📖 As receitas

### 10.0 Como usar e compor as receitas

Cada receita é um `package` próprio e decide sobre o **mesmo contrato de `input`** dos capítulos 3–6 (claims + chamada + contexto). Elas não substituem sua política RBAC/ABAC — **compõem** com ela. Num bundle real, a decisão final costuma exigir todas as dimensões habilitadas:

```rego
package mcp.autorizacao

# ...sua RBAC/ABAC do capítulo 3...

# dimensões extras (receitas que você adotar):
extras_ok if {
	data.cookbook.stepup.decisao.allow
	data.cookbook.quota.decisao.allow
	data.cookbook.janela.decisao.allow
}
```

Adotou uma receita? Ganha os testes dela de graça — e o CI do capítulo 7 já roda tudo.

---

### 10.1 — Step-up: operação de alto valor exige MFA

**O cenário.** Reembolsos normais são rotina. Mas acima de R$ 1.000, o time de risco quer certeza de que é **a pessoa mesmo** — token com autenticação forte (MFA/hardware), não uma sessão de senha que vazou.

**A regra de negócio.**
- Até R$ 1.000 → fluxo normal, qualquer sessão válida;
- Acima de R$ 1.000 → o token precisa declarar contexto de autenticação forte (`acr` — *Authentication Context Class Reference*, claim padrão OIDC: `"mfa"` ou `"hardware"`).

**Como fica** ([`stepup.rego`](../exemplos/policies/cookbook/stepup.rego)):

```rego
package cookbook.stepup

import rego.v1

default decisao := {"allow": false, "reasons": ["sem_regra"]}

decisao := {"allow": true, "reasons": []} if {
	valor <= data.config.limite_stepup
}

decisao := {"allow": true, "reasons": ["stepup_ok"]} if {
	valor > data.config.limite_stepup
	input.claims.acr in {"mfa", "hardware"}
}

decisao := {"allow": false, "reasons": ["exige_mfa"]} if {
	valor > data.config.limite_stepup
	not input.claims.acr in {"mfa", "hardware"}
}

valor := object.get(input.chamada.argumentos, "valor", 0)
```

**Input → decisão** (o limite de R$ 1.000 é `data`, muda sem tocar na política):

```json
{ "claims": {"sub": "ana", "acr": "pwd"}, "chamada": {"argumentos": {"valor": 1500}} }
→ {"allow": false, "reasons": ["exige_mfa"]}

{ "claims": {"sub": "ana", "acr": "mfa"}, "chamada": {"argumentos": {"valor": 1500}} }
→ {"allow": true, "reasons": ["stepup_ok"]}
```

```bash
opa eval -d policies -d data --format raw \
  'data.cookbook.stepup.decisao with input as {"claims": {"sub": "ana", "acr": "pwd"}, "chamada": {"argumentos": {"valor": 1500}}}'
```

**Pegadinha.** `acr` vem do Authorization Server — **não** aceite essa claim vinda de parâmetro de chamada do agente; só de dentro do token validado.

---

### 10.2 — Janela de bloqueio: fechamento contábil

**O cenário.** Toda virada de mês (dias 1–5), o financeiro fecha os livros. Nesse período, nenhuma ferramenta de **escrita** roda — exceto do próprio time de contabilidade, que corrige lançamentos.

**A regra de negócio.**
- Dia do mês ≤ 5 **e** ferramenta de escrita **e** usuário fora da contabilidade → bloqueia;
- Todo o resto (leituras sempre; escrita da contabilidade; dia 6+) → passa.

**Como fica** ([`janela.rego`](../exemplos/policies/cookbook/janela.rego)):

```rego
package cookbook.janela

import rego.v1

default decisao := {"allow": false, "reasons": ["sem_regra"]}

decisao := {"allow": true, "reasons": []} if {
	not bloqueado
}

decisao := {"allow": false, "reasons": ["janela_fechamento"]} if {
	bloqueado
}

bloqueado if {
	em_fechamento
	input.chamada.efeito == "escrita"
	not contabilidade
}

em_fechamento if {
	ts := time.parse_rfc3339_ns(input.contexto.hora)
	time.date(ts, [_, _, dia])        # unifica [ano, mês, dia] — ficamos com o dia
	dia <= 5
}

contabilidade if {
	"contabilidade" in input.claims.grupos
}
```

**Input → decisão:**

```json
{ "claims": {"grupos": ["financeiro"]}, "chamada": {"efeito": "escrita"}, "contexto": {"hora": "2026-10-03T10:00:00Z"} }
→ {"allow": false, "reasons": ["janela_fechamento"]}

{ "claims": {"grupos": ["contabilidade"]}, "chamada": {"efeito": "escrita"}, "contexto": {"hora": "2026-10-03T10:00:00Z"} }
→ {"allow": true, "reasons": []}
```

**Pegadinha.** O `contexto.hora` vem do **PEP** (relógio do servidor), nunca do cliente — senão o agente "viaja no tempo" para fora da janela. E `time.date(ns, [_, _, dia])` unifica a data: assinatura da versão atual do OPA.

---

### 10.3 — Quota diária: agente em loop não derruba a operação

**O cenário.** Um agente de LLM entra em loop e chama a ferramenta de integração 2.400 vezes numa madrugada. O time quer freio **por papel**, não por IP.

**A regra de negócio.**
- Cada papel tem uma cota diária (`analista`: 50; `agente_autonomo`: 200 — são `data`);
- O uso do dia é **fornecido pelo PEP** no contexto; igual ou acima da cota → bloqueia.

**Como fica** ([`quota.rego`](../exemplos/policies/cookbook/quota.rego)):

```rego
package cookbook.quota

import rego.v1

default decisao := {"allow": false, "reasons": ["sem_regra"]}

decisao := {"allow": true, "reasons": []} if {
	input.contexto.uso_diario < limite
}

decisao := {"allow": false, "reasons": ["quota_excedida"]} if {
	input.contexto.uso_diario >= limite
}

limite := data.config.quota_diaria[input.claims.papel]
```

**Input → decisão:**

```json
{ "claims": {"papel": "analista"}, "contexto": {"uso_diario": 50} }
→ {"allow": false, "reasons": ["quota_excedida"]}
```

**Pegadinha — a mais importante do capítulo.** O OPA **não guarda estado**: ele não sabe quantas chamadas já aconteceram. Quem conta é o **PEP** (contador no Valkey, tabela no DocumentDB) e **injeta** no contexto. Isso não é gambiarra — é o desenho: decisão sem estado é determinística, testável e auditável. Estado fica onde já vive.

---

### 10.4 — PII com mascaramento: a decisão que não é só allow/deny

**O cenário.** A ferramenta `consultar_cliente` devolve dados pessoais (LGPD em jogo). Atendimento pode ver o básico; compliance vê tudo; engenharia não vê nada. Não basta bloquear — é preciso dizer **quais campos** cada um recebe.

**A regra de negócio.**
- Papel fora da lista liberada → nem entra;
- Papel liberado → a resposta traz a **lista de campos permitidos** para o **nível** daquele usuário (`publico` / `interno` / `completo`); o PEP projeta os campos antes de responder.

**Como fica** ([`pii.rego`](../exemplos/policies/cookbook/pii.rego)):

```rego
package cookbook.pii

import rego.v1

default resposta := {"allow": false, "reasons": ["rbac_negado"], "campos": []}

resposta := {"allow": true, "reasons": [], "campos": data.pii.campos[input.claims.nivel]} if {
	input.claims.papel in data.pii.papeis_liberados
}
```

Com o `data` ([`cookbook-data.json`](../exemplos/data/cookbook-data.json)):

```json
"pii": {
  "papeis_liberados": ["atendimento", "compliance"],
  "campos": {
    "publico":  ["nome", "cidade"],
    "interno":  ["nome", "cidade", "email", "telefone"],
    "completo": ["nome", "cidade", "email", "telefone", "cpf"]
  }
}
```

**Input → decisão:**

```json
{ "claims": {"papel": "atendimento", "nivel": "publico"} }
→ {"allow": true, "reasons": [], "campos": ["nome", "cidade"]}
```

**Pegadinha.** A decisão rica (`campos`) só protege se o **PEP projetar** a resposta — se ele repassar o documento inteiro e "deixar o cliente filtrar", a política virou figurinha. Teste no PEP, não só na política.

---

### 10.5 — Allowlist de agentes autônomos: ferramentas perigosas

**O cenário.** `executar_migracao`, `rotacionar_credenciais`, `arquivar_projeto` — ferramentas que um agente **autônomo** pode chamar sem humano no circuito. A empresa quer: só **agentes homologados** (registrados no `data`), e **sempre com um humano responsável** atrelado (accountability — quem responde se o agente errar?).

**A regra de negócio.**
- Ferramenta comum → política normal;
- Ferramenta autônoma: exige `agent_id` **na lista de aprovados** (`data`) **e** claim `supervisor` preenchida.

**Como fica** ([`agentes.rego`](../exemplos/policies/cookbook/agentes.rego)):

```rego
package cookbook.agentes

import rego.v1

ferramentas_autonomas := {"executar_migracao", "rotacionar_credenciais", "arquivar_projeto"}

agente_homologado if {
	input.claims.agent_id != ""
	input.claims.agent_id in data.agentes.aprovados
}

tem_supervisor if {
	input.claims.supervisor != ""
}

default decisao := {"allow": false, "reasons": ["sem_regra"]}

decisao := {"allow": true, "reasons": []} if {
	not ferramenta_autonoma
}

decisao := {"allow": true, "reasons": ["agente_homologado"]} if {
	ferramenta_autonoma
	agente_homologado
	tem_supervisor
}

decisao := {"allow": false, "reasons": ["agente_nao_homologado"]} if {
	ferramenta_autonoma
	not agente_homologado
}

decisao := {"allow": false, "reasons": ["sem_supervisor"]} if {
	ferramenta_autonoma
	agente_homologado
	not tem_supervisor
}

ferramenta_autonoma if {
	input.chamada.ferramenta in ferramentas_autonomas
}
```

**Input → decisão:**

```json
{ "claims": {"agent_id": "agent-oncall-02", "supervisor": "carla@empresa.com"}, "chamada": {"ferramenta": "rotacionar_credenciais"} }
→ {"allow": true, "reasons": ["agente_homologado"]}

{ "claims": {"agent_id": "agent-malicioso-99"}, "chamada": {"ferramenta": "executar_migracao"} }
→ {"allow": false, "reasons": ["agente_nao_homologado"]}
```

**Pegadinha.** `agent_id` e `supervisor` são **claims do token** emitidas pelo Authorization Server ao autenticar o agente — nunca argumentos que o próprio agente escolhe.

---

### 10.6 — Break-glass auditado: o acesso de emergência

**O cenário.** Incidente às 3h da manhã: o time precisa rodar a ferramenta agora, e a política RBAC não cobre essa combinação pessoa×ferramenta. A resposta madura **não é** "dou admin para o plantonista" — é um grupo de emergência que **passa por tudo, mas acende o alerta**.

**A regra de negócio.**
- Claim de grupo `break_glass` (atribuída no IdP apenas quando uma emergência é declarada) → `allow` com `"alerta": true` — o PEP dispara pager/alarme e o decision log registra o porquê;
- Sem o grupo → política RBAC normal (aqui reduzida; no real, a do capítulo 3).

**Como fica** ([`breakglass.rego`](../exemplos/policies/cookbook/breakglass.rego)):

```rego
package cookbook.breakglass

import rego.v1

default decisao := {"allow": false, "reasons": ["sem_regra"]}

emergencia if {
	"break_glass" in input.claims.grupos
}

decisao := {"allow": true, "reasons": ["break_glass"], "alerta": true} if {
	emergencia
}

decisao := {"allow": true, "reasons": []} if {
	not emergencia
	autorizacao_padrao
}

decisao := {"allow": false, "reasons": ["rbac_negado"]} if {
	not emergencia
	not autorizacao_padrao
}

# no mundo real: suas rules RBAC/ABAC. Aqui, reduzida:
autorizacao_padrao if {
	input.claims.papel == "financeiro"
}
```

**Input → decisão:**

```json
{ "claims": {"papel": "engenharia", "grupos": ["break_glass"]}, "chamada": {"ferramenta": "qualquer"} }
→ {"allow": true, "reasons": ["break_glass"], "alerta": true}
```

**Pegadinha.** O valor do break-glass está na **trilha**: alerta acionado + decision log com `reasons: ["break_glass"]` + revisão pós-incidente de **toda** decisão marcada. Sem o alarme no PEP, isso é só um bypass com nome bonito.

---

## 🧪 Laboratório 10 — Rodar, quebrar e compor

1. **Rodar tudo:** `opa test policies data -v` → 23/23 (8 da política base + 15 do cookbook);
2. **Reproduzir cada receita** com os comandos `opa eval ... with input as {...}` de cada seção;
3. **Quebrar de propósito:** mude a cota do `analista` para 10 no `cookbook-data.json` e veja qual teste falha (e por que nenhum outro deveria);
4. **Compor** (o exercício que prepara para produção): crie um package `mcp.composta` cuja `decisao` exige `stepup` + `quota` + `janela` ao mesmo tempo, e escreva 2 testes: um caso que passa em tudo e um que nega por quota mas passaria nos outros;
5. **Verificação:** no seu teste composto, a decisão negada deve carregar o reason da dimensão que falhou — se voltar só `"sem_regra"`, a composição engoliu o diagnóstico (dica: faça a composta calcular `reasons` a partir das reasons das receitas).

## Próximos passos

- As receitas entram no bundle como qualquer política — o pipeline do [capítulo 7](cap-07-operacao.md) não muda;
- A empresa tem um caso que não encaixa em nenhuma receita? Descreva para o agente — às vezes é variação de uma destas (e aí entra no seu fork do cookbook).

## 📚 Fontes

- [OPA — Policy Language](https://openpolicyagent.org/docs/policy-language)
- [OPA — builtin `time.*`](https://www.openpolicyagent.org/docs/latest/policy-reference/#time)
- [OIDC — claim `acr` (Authentication Context Class Reference)](https://openid.net/specs/openid-connect-core-1_0.html#acrSemantics)
- [LGPD — princípio da necessidade (art. 6º, III)](https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2018/lei/l13709.htm)
