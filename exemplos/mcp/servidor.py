# Servidor MCP de faturamento (exemplo do curso) — PEP que consulta o OPA (PDP).
#
# O que este exemplo isola: a mecânica de autorização por ferramenta.
# Ferramentas são expostas como POST /tools/{ferramenta} para simplificar o
# laboratório; em produção, o transporte real é o do SDK oficial do MCP
# (Streamable HTTP), com o MESMO padrão: middleware valida o JWT (OAuth 2.1),
# autorizar() consulta o OPA antes de executar, e falha de OPA é fail-closed.
#
# Rodar (com o OPA já ativo em OPA_URL):
#   uvicorn servidor:app --port 8000
import os
import logging

import httpx
import jwt
from fastapi import FastAPI, HTTPException, Request

OPA_URL = os.environ.get("OPA_URL", "http://127.0.0.1:8181")
OPA_PATH = os.environ.get("OPA_PATH", "mcp/autorizacao/decisao")
AMBIENTE = os.environ.get("AMBIENTE", "dev")
JWT_SECRET = os.environ.get("JWT_SECRET", "segredo-so-de-lab-0123456789abcdef0123456789abcdef")  # produção: AS real (RS256/JWKS)

log = logging.getLogger("mcp")

app = FastAPI(title="mcp-faturamento (exemplo do curso OPA)")


# ---------------------------------------------------------- authn (OAuth 2.1)
def claims_do_token(request: Request) -> dict:
    """Valida o bearer token e devolve as claims. 401 = autenticação falhou."""
    auth = request.headers.get("Authorization", "")
    if not auth.startswith("Bearer "):
        raise HTTPException(401, "bearer token ausente")
    try:
        return jwt.decode(
            auth.removeprefix("Bearer "),
            JWT_SECRET,
            algorithms=["HS256"],
            audience="mcp-faturamento",
        )
    except jwt.InvalidTokenError as e:
        raise HTTPException(401, f"token invalido: {e}") from e


# ------------------------------------------------------------------- PEP
def autorizar(claims: dict, ferramenta: str, argumentos: dict) -> dict:
    """Consulta o PDP e aplica a decisão. Fail-closed: sem OPA, sem acesso."""
    entrada = {
        "claims": claims,
        "chamada": {"ferramenta": ferramenta, "argumentos": argumentos},
        "contexto": {"origem": "mcp-faturamento", "ambiente": AMBIENTE},
    }
    try:
        resp = httpx.post(
            f"{OPA_URL}/v1/data/{OPA_PATH}",
            json={"input": entrada},
            timeout=2.0,
        )
        resp.raise_for_status()
        decisao = resp.json().get(
            "result", {"allow": False, "reasons": ["opa_sem_resposta"]}
        )
    except httpx.HTTPError as e:
        log.critical("fail-closed: OPA indisponivel (%s)", e)
        raise HTTPException(503, "autorizacao indisponivel") from e
    if not decisao.get("allow", False):
        raise HTTPException(403, f"negado: {decisao.get('reasons')}")
    return decisao


# -------------------------------------------------------------- ferramentas
FATURAS_FAKE = {
    "proj-41": [{"id": "F-1001", "valor": 320.0, "status": "paga"}],
    "proj-99": [{"id": "F-2002", "valor": 80.0, "status": "aberta"}],
}


@app.get("/healthz")
def healthz():
    return {"ok": True, "ambiente": AMBIENTE, "opa": OPA_URL}


@app.post("/tools/listar_faturas")
def listar_faturas(request: Request, body: dict):
    claims = claims_do_token(request)
    autorizar(claims, "listar_faturas", body)
    return {"faturas": FATURAS_FAKE.get(body.get("projeto_id", ""), [])}


@app.post("/tools/emitir_reembolso")
def emitir_reembolso(request: Request, body: dict):
    claims = claims_do_token(request)
    autorizar(
        claims,
        "emitir_reembolso",
        {
            "projeto_id": body.get("projeto_id"),
            "valor": body.get("valor"),
            "motivo": body.get("motivo"),
        },
    )
    return {"reembolso": "emitido", "projeto": body.get("projeto_id"), "valor": body.get("valor")}


@app.post("/tools/fechar_mes")
def fechar_mes(request: Request, body: dict):
    claims = claims_do_token(request)
    autorizar(claims, "fechar_mes", body)
    return {"mes": body.get("mes"), "fechado": True}
