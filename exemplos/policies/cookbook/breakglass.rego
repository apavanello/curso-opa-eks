# RECEITA 6 — Break-glass auditado (cookbook.breakglass)
#
# Case: incidente às 3h da manhã. O grupo "break_glass" (atribuído no IdP
# apenas durante emergências declaradas) passa por QUALQUER ferramenta —
# mas a decisão carrega alerta=true para o PEP disparar alarme/pager.
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

# no mundo real: suas rules RBAC/ABAC do capítulo 3. Aqui, reduzida:
autorizacao_padrao if {
	input.claims.papel == "financeiro"
}
