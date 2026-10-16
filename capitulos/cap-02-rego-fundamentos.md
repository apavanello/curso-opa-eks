# Capítulo 2 — Rego do zero

> No capítulo 1 você avaliou uma política sem entendê-la. Agora entendemos a linguagem **Rego**: como o OPA raciocina sobre JSON, o que são *rules*, por que "falso" em Rego costuma ser **ausência** (negação por falha), e por que toda política de autorização termina em `default allow := false`. No laboratório você escreve e depura suas primeiras regras com `opa eval`.

## 🎯 Objetivos

- Ler e escrever Rego: **packages**, **rules**, **valores** e **variáveis**;
- Entender **unificação** e o fluxo de avaliação declarativa;
- Dominar a **negação por falha** — a semântica que mais confunde iniciantes;
- Aplicar o padrão de segurança fundamental: `default allow := false`;
- Usar `some`/`in`, operadores e **comprehensions**;
- Trabalhar com `opa eval`, o REPL (`opa run`) e `opa fmt`.

## 📖 Conteúdo

### 2.1 Rego é consulta sobre JSON

Rego (diz-se *"rê-go"*, da linguagem Rego — [docs oficiais](https://openpolicyagent.org/docs/policy-language)) é uma linguagem **declarativa** derivada de Datalog, feita para *consultar* documentos JSON. Em vez de descrever *como* decidir (passos), você descreve **quando uma afirmação é verdadeira**.

Todo o material do curso segue a **sintaxe Rego v1** (padrão desde o OPA 1.0; em versões antigas via `import rego.v1`). Se você ver policies antigas com `allow { ... }` sem `if`, é a sintaxe legada — ainda comum em blogs:

```rego
# Sintaxe v1 (este curso)          # Sintaxe legada (OPA < 1.0)
allow if {                          allow {
    input.user == "ana"                 input.user == "ana"
}                                   }
```

Estrutura mínima de um arquivo `.rego`:

```rego
package mcp.autorizacao        # 1. namespace — onde a policy vive no OPA

import rego.v1                 # 2. (opcional em OPA 1.0+) habilita sintaxe v1

default allow := false         # 3. valor padrão — o quando-nada-casa

allow if {                     # 4. rule: TRUE quando o corpo for verdadeiro
    input.usuario == "ana"
    input.acao == "listar_faturas"
}
```

Avaliação (repetindo o ciclo do capítulo 1):

```bash
opa eval --data policy.rego --input input.json 'data.mcp.autorizacao.allow'
```

### 2.2 Rules: documentos virtuais

Em Rego, tudo que você declara é um **documento**. O `input` e o `data` são documentos *reais* (fornecidos de fora); suas rules criam documentos **virtuais** — valores calculados sob demanda, montados em `data.<package>.<rule>`:

```rego
package mcp.autorizacao

# rule booleana (documento virtual booleano)
somente_leitura if {
    input.acao in {"listar_faturas", "ver_reembolso"}
}

# rule com valor (documento virtual com conteúdo)
usuario_descricao := sprintf("usuario=%s acao=%s", [input.usuario, input.acao]) if {
    input.usuario != ""
}
```

Regras do jogo:

- Uma rule **sem valor declarado** é booleana: verdadeira se o corpo casar;
- Uma rule **com `:=`** produz o valor do lado direito quando o corpo casar;
- **Múltiplos corpos para a mesma rule = OR**: basta um casar, a rule é verdadeira. É assim que se escreve "qualquer uma das condições":

```rego
pode_ver_faturas if {
    input.papel == "financeiro"
}

pode_ver_faturas if {
    input.papel == "auditor"
}
# pode_ver_faturas é true para financeiro OU auditor
```

> 💡 **Sem OR/AND explícitos:** linhas dentro de um corpo são **AND** (todas precisam casar); rules repetidas são **OR**. Não existe `||` — existe esse padrão.

### 2.3 Unificação: variáveis "casam", não "recebem"

Uma variável Rego (`x := ...`) não é uma atribuição imperativa: o motor **unifica** — procura valores que tornem as expressões verdadeiras ([docs — language basics](https://openpolicyagent.org/docs/policy-language/)):

```rego
# "existe alguma ferramenta no catálogo cujo nome é a ação pedida?"
acao_valida if {
    some ferramenta in data.catalogo.ferramentas
    ferramenta.nome == input.acao
}
```

Leia `some ferramenta in ...` como: *"existe um `ferramenta` na lista tal que as linhas abaixo são verdadeiras"*. Se existe → `acao_valida` é true. Se não → a rule **falha** (é indefinida). Variáveis não declaradas em `some` mas usadas pela primeira vez numa expressão são vinculadas por unificação implícita:

```rego
dono_do_projeto := dono if {
    projeto := data.projetos[input.projeto_id]   # projeto se liga ao item do object
    dono := projeto.dono
}
```

### 2.4 Negação por falha (a semântica-chave)

Rego não tem "false" explícito dentro de corpos — tem **indefinição** ([docs — negation](https://openpolicyagent.org/docs/policy-language/#negation)). Uma expressão que não casa torna a rule **indefinida** (o documento simplesmente não existe para aquele input):

```rego
allow if {
    input.papel == "admin"
    not bloqueado            # "bloqueado é falso/indefinido" = negação por falha
}

bloqueado if {
    input.usuario in data.lista_negra
}
```

- `not X` significa: **"X não é verdadeiro"** — cobre tanto "X é falso" quanto "X não existe";
- ⚠️ O erro clássico: `not input.valor == "x"` vs. `not f(x)` — dentro do `not` só cabe uma **expressão** (uma comparação ou uma chamada de rule), nunca um bloco;
- ⚠️ **Uma rule indefinida não é `false`**: `opa eval` retorna sem `result`. Por isso o curso usa sempre `default` — o próximo tópico.

### 2.5 `default allow := false` (o padrão mais importante do curso)

Sem `default`, uma consulta a `allow` que não casa nenhuma rule é **indefinida** — e seu PEP teria que interpretar ausência. Com `default`, você fixa o valor do "não casou":

```rego
package mcp.autorizacao

default allow := false

allow if {
    acao_valida
    usuario_autorizado
}
```

A partir daqui, **toda política de autorização deste curso tem essa cara**: negado por padrão, permitido apenas quando todas as condições casarem. Fail-closed nasce aqui, na linguagem — não no deploy.

### 2.6 Ferramentas do dia a dia

**`opa eval`** — avaliar queries (o `jq` do Rego):

```bash
# valor limpo
opa eval --data policy.rego --input input.json --format raw \
  'data.mcp.autorizacao.allow'

# inspecionar um pedaço do input/data (depuração!)
opa eval --input input.json --format raw 'input.acao'
opa eval --data data.json --format raw 'data.projetos'
```

**REPL** (`opa run`) — experimentação interativa:

```bash
opa run policy.rego data.json
# no prompt:
# > data.mcp.autorizacao.allow
# > input.acao      (input via: opa run --set-input input.json ... ou 'with input as ...')
# > show            (mostra o documento data completo)
```

**`opa fmt`** — formatação canônica (roda no CI, como `terraform fmt`):

```bash
opa fmt --write policy.rego
```

### 2.7 Comprehensions e agregações

Comprehensions constroem coleções a partir de outras — aparecem em toda política com listas:

```rego
# array comprehension: projetos do usuário
meus_projetos := [nome |
    some nome, info in data.projetos
    info.dono == input.usuario
]

# set comprehension: ações permitidas segundo o papel
acoes_permitidas := {acao |
    some permissao in data.papeis[input.papel]
    acao := permissao.acao
}

# agregação: quantas ferramentas perigosas nesta chamada?
total_perigosas := count([f | some f in input.ferramentas; f.risco == "alto"])
```

Operadores úteis: `in` (membro), `count()`, `sprintf()`, `lower()`, `startswith()`, comparações (`<`, `>=`…), aritmética. A lista completa está no [cheatsheet (Apêndice A)](../apendices/apendice-a-cheatsheet-rego.md).

### 2.8 Funções (para reutilizar lógica)

```rego
# função com argumentos — chame como uma built-in
mesmo_projeto(a, b) if {
    data.projetos[a].tenant == data.projetos[b].tenant
}

allow if {
    mesmo_projeto(input.projeto_origem, input.projeto_destino)
    input.acao == "transferir_fatura"
}
```

> ⚠️ Funções são **puras** (sem efeito, só decidem) e não viram documentos virtuais — não aparecem em `data.<package>` para consulta externa.

## 🧪 Laboratório 2 — Sua primeira política de verdade

Crie `lab/policy.rego`:

```rego
package lab

import rego.v1

default permitir := false

permitir if {
    input.acao in acoes_do_papel
}

acoes_do_papel := {acao |
    some p in data.papeis[input.papel]
    acao := p
}
```

Crie `lab/data.json`:

```json
{
  "papeis": {
    "financeiro": ["listar_faturas", "ver_reembolso"],
    "admin": ["listar_faturas", "ver_reembolso", "emitir_reembolso", "fechar_mes"]
  }
}
```

Tarefas (verifique cada uma com `opa eval --format raw`):

1. `input = {"papel": "financeiro", "acao": "listar_faturas"}` → deve dar `true`;
2. `{"papel": "financeiro", "acao": "emitir_reembolso"}` → `false` (default entrou em ação);
3. `{"papel": "rh", "acao": "listar_faturas"}` → `false` — papel desconhecido, `data.papeis["rh"]` é indefinido e a comprehension vira conjunto vazio;
4. No REPL, inspecione `data.lab.acoes_do_papel` com cada input e entenda o *porquê* de cada resultado;
5. **Desafio:** adicione uma rule `motivo` que retorne `"papel_desconhecido"` quando `data.papeis[input.papel]` for indefinido. Dica: `not data.papeis[input.papel]` e `motivo := "..."` — ou espere a forma canônica no capítulo 3.

## Próximos passos

- **[Capítulo 3 — Rego para autorização](cap-03-rego-autorizacao.md):** o laboratório 2 vira uma política de API real: validação de JWT, RBAC + ABAC e decisão pelos **argumentos** da ferramenta MCP;
- Travou na unificação ou na negação por falha? Pergunte ao seu agente com o trecho de política que não funciona — correção de Rego é o trabalho dele.

## 📚 Fontes

- [OPA — Policy Language (docs oficiais)](https://openpolicyagent.org/docs/policy-language)
- [The Rego Language — cheat sheet oficial (PDF)](https://www.openpolicyagent.org/docs/latest/policy-cheat-sheet/)
- [Spacelift — Open Policy Agent Rego Tutorial](https://spacelift.io/blog/open-policy-agent-rego)
- [Snyk — Rego 101](https://snyk.io/blog/introduction-to-rego)
