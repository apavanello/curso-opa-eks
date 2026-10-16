# Testes da política do MCP de faturamento — cobrem a matriz de decisão do capítulo 6.
# Rode com: opa test exemplos/policies -v
package mcp.autorizacao_test

import rego.v1

import data.mcp.autorizacao

claims_ana := {
	"sub": "ana@empresa.com",
	"scope": "mcp:faturamento",
	"equipe": "financeiro",
}

claims_bruno := {
	"sub": "bruno@empresa.com",
	"scope": "mcp:faturamento",
	"equipe": "engenharia",
}

claims_carla := {
	"sub": "carla@empresa.com",
	"scope": "mcp:faturamento",
	"equipe": "financeiro",
}

chamada(ferramenta, argumentos) := {"ferramenta": ferramenta, "argumentos": argumentos}

# ---- caso 1: ana lista faturas do próprio projeto → allow
test_ana_lista_faturas_ok if {
	autorizacao.decisao with input as {
		"claims": claims_ana,
		"chamada": chamada("listar_faturas", {"projeto_id": "proj-41"}),
		"contexto": {"ambiente": "prod"},
	} == {"allow": true, "reasons": []}
}

# ---- caso 2: ana emite reembolso acima do limite de prod → limite_excedido
test_ana_reembolso_acima_do_limite if {
	decisao := autorizacao.decisao with input as {
		"claims": claims_ana,
		"chamada": chamada("emitir_reembolso", {"projeto_id": "proj-41", "valor": 600}),
		"contexto": {"ambiente": "prod"},
	}
	decisao.allow == false
	decisao.reasons == ["limite_excedido"]
}

# ---- caso 3: bruno (engenharia) tenta listar faturas → rbac_negado
test_bruno_sem_vinculo_rbac if {
	decisao := autorizacao.decisao with input as {
		"claims": claims_bruno,
		"chamada": chamada("listar_faturas", {"projeto_id": "proj-41"}),
		"contexto": {"ambiente": "prod"},
	}
	decisao.allow == false
	decisao.reasons == ["rbac_negado"]
}

# ---- caso 4: ana emite reembolso em projeto de outra equipe → projeto_negado
test_ana_projeto_de_outra_equipe if {
	decisao := autorizacao.decisao with input as {
		"claims": claims_ana,
		"chamada": chamada("emitir_reembolso", {"projeto_id": "proj-99", "valor": 450}),
		"contexto": {"ambiente": "prod"},
	}
	decisao.allow == false
	decisao.reasons == ["projeto_negado"]
}

# ---- caso 5: ana emite reembolso dentro do limite → allow
test_ana_reembolso_dentro_do_limite if {
	autorizacao.decisao with input as {
		"claims": claims_ana,
		"chamada": chamada("emitir_reembolso", {"projeto_id": "proj-41", "valor": 450}),
		"contexto": {"ambiente": "prod"},
	} == {"allow": true, "reasons": []}
}

# ---- caso 6: sem scope do MCP → token_invalido (autorização grossa falhou)
test_sem_scope_token_invalido if {
	decisao := autorizacao.decisao with input as {
		"claims": {"sub": "ana@empresa.com", "scope": "outro", "equipe": "financeiro"},
		"chamada": chamada("listar_faturas", {"projeto_id": "proj-41"}),
		"contexto": {"ambiente": "prod"},
	}
	decisao.allow == false
	decisao.reasons == ["token_invalido"]
}

# ---- caso 7: carla (admin_financeiro, wildcard) fecha o mês em dev → allow
test_carla_admin_fecha_mes if {
	autorizacao.decisao with input as {
		"claims": claims_carla,
		"chamada": chamada("fechar_mes", {"mes": "2026-09"}),
		"contexto": {"ambiente": "dev"},
	} == {"allow": true, "reasons": []}
}

# ---- caso 8: dev tem limite menor — 450 em dev estoura (100)
test_limite_menor_em_dev if {
	decisao := autorizacao.decisao with input as {
		"claims": claims_carla,
		"chamada": chamada("emitir_reembolso", {"projeto_id": "proj-41", "valor": 450}),
		"contexto": {"ambiente": "dev"},
	}
	decisao.allow == false
	decisao.reasons == ["limite_excedido"]
}
