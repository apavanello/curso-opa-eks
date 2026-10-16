# RECEITA 2 — Janela de bloqueio: fechamento contábil (cookbook.janela)
#
# Case: dias 1–5 do mês é fechamento contábil. Durante a janela, ferramentas
# de ESCRITA ficam bloqueadas para todo mundo, exceto o time de contabilidade.
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
	time.date(ts, [_, _, dia])
	dia <= 5
}

contabilidade if {
	"contabilidade" in input.claims.grupos
}
