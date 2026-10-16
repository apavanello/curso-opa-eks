# RECEITA 5 — Allowlist de agentes autônomos (cookbook.agentes)
#
# Case: certas ferramentas perigosas (migrar, rotacionar credenciais) só
# podem ser chamadas por AGENTES homologados (agent_id no token) e sempre
# com um humano responsável registrado (supervisor) — accountability.
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
