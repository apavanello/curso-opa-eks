# Política de autorização do MCP de faturamento — curso OPA para MCPs no EKS
#
# Contrato do input (montado pelo PEP — servidor MCP):
#   {
#     "claims":   { "sub": "...", "scope": "mcp:faturamento", "equipe": "..." },
#     "chamada":  { "ferramenta": "...", "argumentos": { ... } },
#     "contexto": { "origem": "mcp-faturamento", "ambiente": "dev|prod" }
#   }
#
# Em produção, as claims chegam APÓS o middleware validar o JWT (OAuth 2.1).
# Aqui, claims_validas verifica o mínimo: identidade + scope da autorização grossa.
package mcp.autorizacao

import rego.v1

# ------------------------------------------------------------------ decisão
# Regras de `decisao` são mutuamente exclusivas (cada uma exige `not` da
# dimensão anterior): prioridade token > rbac > projeto > limite.

default decisao := {"allow": false, "reasons": ["sem_regra"]}

decisao := {"allow": true, "reasons": []} if {
	claims_validas
	rbac_ok
	projeto_ok
	limite_ok
}

decisao := {"allow": false, "reasons": ["token_invalido"]} if {
	not claims_validas
}

decisao := {"allow": false, "reasons": ["rbac_negado"]} if {
	claims_validas
	not rbac_ok
}

decisao := {"allow": false, "reasons": ["projeto_negado"]} if {
	claims_validas
	rbac_ok
	not projeto_ok
}

decisao := {"allow": false, "reasons": ["limite_excedido"]} if {
	claims_validas
	rbac_ok
	projeto_ok
	not limite_ok
}

# ---------------------------------------------------- authn (autorização grossa)
claims_validas if {
	input.claims.sub != ""
	contains(input.claims.scope, "mcp:faturamento")
}

usuario := input.claims.sub if {
	claims_validas
}

# ---------------------------------------------------------------- RBAC
rbac_ok if {
	some papel in data.rbac.vinculos[usuario]
	some permissao in data.rbac.papeis[papel].permissoes
	permissao.efeito == "permitir"
	ferramenta_concede(permissao.ferramenta)
}

ferramenta_concede(padrao) if padrao == "*"

ferramenta_concede(padrao) if padrao == input.chamada.ferramenta

# ---------------------------------------------------------------- ABAC: projeto
projeto_requerido if {
	input.chamada.ferramenta in {"listar_faturas", "ver_reembolso", "emitir_reembolso"}
}

projeto_ok if {
	not projeto_requerido
}

projeto_ok if {
	projeto_requerido
	projeto_id := object.get(input.chamada.argumentos, "projeto_id", "")
	projeto_id != ""
	data.projetos[projeto_id].equipe == input.claims.equipe
}

# ---------------------------------------------------------------- ABAC: limite
ferramenta_com_valor if {
	input.chamada.ferramenta == "emitir_reembolso"
}

limite_ok if {
	not ferramenta_com_valor
}

limite_ok if {
	ferramenta_com_valor
	valor := object.get(input.chamada.argumentos, "valor", 0)
	valor > 0
	valor <= data.limites[input.contexto.ambiente].reembolso_max
}
