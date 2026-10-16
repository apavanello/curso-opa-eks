# RECEITA 4 — PII com mascaramento de campos (cookbook.pii)
#
# Case: a ferramenta "consultar_cliente" expõe dados pessoais (LGPD). A
# decisão não é só allow/deny: ela diz QUAIS CAMPOS a resposta pode conter.
# O PEP (servidor MCP) projeta os campos antes de devolver ao agente.
package cookbook.pii

import rego.v1

default resposta := {"allow": false, "reasons": ["rbac_negado"], "campos": []}

resposta := {"allow": true, "reasons": [], "campos": data.pii.campos[input.claims.nivel]} if {
	input.claims.papel in data.pii.papeis_liberados
}
