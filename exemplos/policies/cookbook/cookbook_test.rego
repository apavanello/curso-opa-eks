# Testes do cookbook — uma receita, pelo menos um caso positivo e um negativo.
package cookbook_test

import rego.v1

import data.cookbook

# ---- receita 1: step-up
test_stepup_valor_alto_com_mfa if {
	cookbook.stepup.decisao with input as {
		"claims": {"sub": "ana", "acr": "mfa"},
		"chamada": {"argumentos": {"valor": 1500}},
	} == {"allow": true, "reasons": ["stepup_ok"]}
}

test_stepup_valor_alto_sem_mfa if {
	d := cookbook.stepup.decisao with input as {
		"claims": {"sub": "ana", "acr": "pwd"},
		"chamada": {"argumentos": {"valor": 1500}},
	}
	d.reasons == ["exige_mfa"]
}

test_stepup_valor_baixo_passa_sem_mfa if {
	cookbook.stepup.decisao with input as {
		"claims": {"sub": "ana", "acr": "pwd"},
		"chamada": {"argumentos": {"valor": 200}},
	} == {"allow": true, "reasons": []}
}

# ---- receita 2: janela de fechamento (dia 3 = fechamento)
test_janela_escrita_bloqueada_no_fechamento if {
	d := cookbook.janela.decisao with input as {
		"claims": {"sub": "ana", "grupos": ["financeiro"]},
		"chamada": {"efeito": "escrita"},
		"contexto": {"hora": "2026-10-03T10:00:00Z"},
	}
	d.reasons == ["janela_fechamento"]
}

test_janela_contabilidade_passa if {
	cookbook.janela.decisao with input as {
		"claims": {"sub": "claudia", "grupos": ["contabilidade"]},
		"chamada": {"efeito": "escrita"},
		"contexto": {"hora": "2026-10-03T10:00:00Z"},
	} == {"allow": true, "reasons": []}
}

test_janela_leitura_sempre_passa if {
	cookbook.janela.decisao with input as {
		"claims": {"sub": "ana", "grupos": ["financeiro"]},
		"chamada": {"efeito": "leitura"},
		"contexto": {"hora": "2026-10-03T10:00:00Z"},
	} == {"allow": true, "reasons": []}
}

# ---- receita 3: quota
test_quota_dentro_do_limite if {
	cookbook.quota.decisao with input as {
		"claims": {"sub": "ana", "papel": "analista"},
		"contexto": {"uso_diario": 49},
	} == {"allow": true, "reasons": []}
}

test_quota_estourada if {
	d := cookbook.quota.decisao with input as {
		"claims": {"sub": "ana", "papel": "analista"},
		"contexto": {"uso_diario": 50},
	}
	d.reasons == ["quota_excedida"]
}

# ---- receita 4: PII
test_pii_nivel_publico if {
	cookbook.pii.resposta with input as {
		"claims": {"sub": "bia", "papel": "atendimento", "nivel": "publico"},
	} == {"allow": true, "reasons": [], "campos": ["nome", "cidade"]}
}

test_pii_papel_nao_liberado if {
	d := cookbook.pii.resposta with input as {
		"claims": {"sub": "bruno", "papel": "engenharia", "nivel": "publico"},
	}
	d.allow == false
}

# ---- receita 5: agentes
test_agente_homologado_com_supervisor if {
	cookbook.agentes.decisao with input as {
		"claims": {"sub": "agente", "agent_id": "agent-oncall-02", "supervisor": "carla@empresa.com"},
		"chamada": {"ferramenta": "rotacionar_credenciais"},
	} == {"allow": true, "reasons": ["agente_homologado"]}
}

test_agente_homologado_sem_supervisor if {
	d := cookbook.agentes.decisao with input as {
		"claims": {"sub": "agente", "agent_id": "agent-oncall-02"},
		"chamada": {"ferramenta": "rotacionar_credenciais"},
	}
	d.reasons == ["sem_supervisor"]
}

test_agente_desconhecido if {
	d := cookbook.agentes.decisao with input as {
		"claims": {"sub": "agente", "agent_id": "agent-malicioso-99"},
		"chamada": {"ferramenta": "executar_migracao"},
	}
	d.reasons == ["agente_nao_homologado"]
}

# ---- receita 6: break-glass
test_breakglass_passa_com_alerta if {
	cookbook.breakglass.decisao with input as {
		"claims": {"sub": "carla", "papel": "engenharia", "grupos": ["break_glass"]},
		"chamada": {"ferramenta": "qualquer"},
	} == {"allow": true, "reasons": ["break_glass"], "alerta": true}
}

test_breakglass_sem_grupo_segue_rbac if {
	cookbook.breakglass.decisao with input as {
		"claims": {"sub": "ana", "papel": "financeiro", "grupos": []},
		"chamada": {"ferramenta": "qualquer"},
	} == {"allow": true, "reasons": []}
}
