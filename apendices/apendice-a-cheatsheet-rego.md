# Apêndice A — Cheatsheet de Rego

> Uma página para consultar enquanto escreve política. Sintaxe **Rego v1** (OPA ≥ 1.0). Fonte primária: [docs oficiais](https://openpolicyagent.org/docs/policy-language) e o [cheat sheet oficial](https://www.openpolicyagent.org/docs/latest/policy-cheat-sheet/).

## Estrutura de um arquivo

```rego
package mcp.autorizacao        # namespace → vira data.mcp.autorizacao

import rego.v1                 # implícito no OPA 1.0+

default decisao := {"allow": false, "reasons": ["sem_regra"]}   # quando nada casa
```

## Rules

```rego
# booleana — verdadeira se o corpo casar
allow if {
    input.usuario == "ana"
}

# com valor — produz o valor quando o corpo casar
dono := projeto.dono if {
    projeto := data.projetos[input.projeto_id]
}

# múltiplos corpos com valor DEVEM ser mutuamente exclusivos
decisao := {"allow": true} if { todas_as_condicoes }
decisao := {"allow": false, "reasons": ["rbac"]} if { not todas_as_condicoes }

# senão (else) — alternativa às múltiplas rules
permitido := "sim" if { cond_a } else := "parcial" if { cond_b } else := "nao"

# funções (não viram documento virtual; são puras)
mesmo_time(a, b) if { a.equipe == b.equipe }
```

## Lógica

```rego
# AND  → linhas no mesmo corpo
allow if {
    cond_a
    cond_b
}

# OR   → rules repetidas
pode if { input.papel == "admin" }
pode if { input.papel == "financeiro" }

# NOT  → negação por falha (não é booleano, é "não é verdade")
nao_bloqueado if { not bloqueado }
```

## Variáveis, coleções, iteração

```rego
some x in lista                          # existe item (iteração)
some chave, valor in objeto              # iteração de object
x := data.vinculos[input.usuario]        # vínculo direto
aprovados := {u | some u in data.users; u.ativo}     # set comprehension
nomes := [u.nome | some u in data.users]             # array comprehension
m := {u.nome: u.papel | some u in data.users}        # object comprehension

count(colecao)                           # tamanho
"ana" in vinculos                        # membership
objeto.chave                             # acesso; INDEFINIDO se não existe
object.get(objeto, "chave", "padrao")    # acesso com default (evita indefinição!)
```

## Operadores e built-ins que mais aparecem

```rego
==  !=  <  <=  >  >=      comparação
+ - * /                   aritmética
startswith(s, pre)  endswith(s, suf)  contains(s, sub)  lower(s)  upper(s)
sprintf("x=%v", [x])      formatar
split(s, ",")  trim(s, " ")
time.parse_rfc3339_ns("2026-10-16T14:30:00Z")   # → nanossegundos comparáveis
time.now_ns()
json.marshal(x)  json.unmarshal(s)
```

## JWT

```rego
# decodificar sem validar (payload/header legíveis)
[true, header, payload] := io.jwt.decode(input.token)

# validar HMAC (HS256) + exp/nbf + audience/issuer
io.jwt.verify_hs256(input.token, data.segredos.hmac)
[true, _, payload] := io.jwt.decode_verify(input.token, {"aud": ["mcp"], "iss": "..."})

# RS256 com chave pública (JWKS no data, atualizado via bundle)
io.jwt.verify_rs256(input.token, json.marshal(jwk))
```

## Testes

```rego
package mcp.autorizacao_test
import rego.v1
import data.mcp.autorizacao

test_qualquer_nome if {
    autorizacao.decisao with input as {"claims": {"sub": "ana"}, ...}
        == {"allow": true, "reasons": []}
}

# mockar built-in no teste:
test_token_invalido if {
    not autorizacao.ok with input as {...} with io.jwt.verify_hs256 as false
}
```

```bash
opa test policies data -v        # rodar testes (política E dados)
opa fmt --write f.rego           # formatar
opa fmt --fail policies/         # falha se não formatado (CI)
opa check --strict policies/     # lint
opa eval -d policies -d data/data.json -i input.json --format raw 'data.mcp.x.allow'
opa run --server -a 127.0.0.1:8181 policies data.json    # servidor
opa build -b bundle/ -r v42 -o bundle.tar.gz             # bundle com revision
```

## Padrões de autorização (resumo do curso)

```rego
default decisao := {"allow": false, "reasons": ["sem_regra"]}

decisao := {"allow": true, "reasons": []} if {
    claims_validas        # authn (token validado pelo PEP, scope ok)
    rbac_ok               # papel → permissão → ferramenta
    projeto_ok            # ABAC: recurso pertence ao time do usuário
    limite_ok             # ABAC: argumentos dentro do limite do ambiente
}
# ...uma rule de deny por dimensão, mutuamente exclusivas, com reason própria
```
