# Data filtering para DocumentDB (API MongoDB) — capítulo 8.
#
# Diferente das políticas de decisão (allow/deny), esta política descreve
# QUAIS DOCUMENTOS o usuário pode ver. A aplicação chama a Compile API com
# unknowns=["input.documento"] e recebe as condições traduzíveis para um
# filtro find() do MongoDB/DocumentDB.
package documentdb.filtros

import rego.v1

default include := false

# documento visível se: a equipe dona está entre as equipes do usuário
# E o status do documento é visível para o papel dele
include if {
	some equipe in input.claims.equipes
	input.documento.equipe == equipe
	input.documento.status in status_visivel[input.claims.papel]
}

status_visivel := {
	"financeiro": {"aberta", "paga", "revisao"},
	"auditor": {"paga", "revisao"},
}
