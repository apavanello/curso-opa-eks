# RECEITA 3 — Quota diária por papel (cookbook.quota)
#
# Case: agentes de LLM podem entrar em loop e martelar ferramentas caras.
# O PEP mantém o contador (ex.: no Valkey) e injeta no contexto a cada
# chamada. O OPA apenas decide sobre o número — ele NÃO guarda estado.
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
