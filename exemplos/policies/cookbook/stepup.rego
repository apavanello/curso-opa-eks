# RECEITA 1 — Step-up auth para operações de alto valor (cookbook.stepup)
#
# Case: reembolso/deploy acima de R$ 1.000 exige autenticação forte (MFA),
# comprovada pela claim "acr" (Authentication Context Class Reference, OIDC).
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
