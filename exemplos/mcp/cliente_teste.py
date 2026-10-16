# Cliente de teste — executa a matriz de decisão do capítulo 6 contra o
# servidor MCP + OPA do laboratório e confere o resultado esperado.
#
#   python cliente_teste.py
#
# Espera: OPA em http://127.0.0.1:8181 e servidor.py em http://127.0.0.1:8000.
import sys

import httpx
import jwt

MCP = "http://127.0.0.1:8000"
SECRET = "segredo-so-de-lab-0123456789abcdef0123456789abcdef"

USUARIOS = {
    "ana": {"sub": "ana@empresa.com", "scope": "mcp:faturamento", "equipe": "financeiro"},
    "bruno": {"sub": "bruno@empresa.com", "scope": "mcp:faturamento", "equipe": "engenharia"},
    "carla": {"sub": "carla@empresa.com", "scope": "mcp:faturamento", "equipe": "financeiro"},
}


def token(usuario: str) -> str:
    claims = {**USUARIOS[usuario], "aud": "mcp-faturamento"}
    return jwt.encode(claims, SECRET, algorithm="HS256")


# (descrição, usuario, ferramenta, argumentos, esperado_allow, esperado_reason)
MATRIZ = [
    ("1. ana lista faturas do próprio projeto", "ana", "listar_faturas",
     {"projeto_id": "proj-41"}, True, None),
    ("2. ana emite reembolso acima do limite (prod=500)", "ana", "emitir_reembolso",
     {"projeto_id": "proj-41", "valor": 600, "motivo": "servidor"}, False, "limite_excedido"),
    ("3. bruno (engenharia) tenta listar faturas", "bruno", "listar_faturas",
     {"projeto_id": "proj-41"}, False, "rbac_negado"),
    ("4. ana emite reembolso em projeto de outra equipe", "ana", "emitir_reembolso",
     {"projeto_id": "proj-99", "valor": 450, "motivo": "curso"}, False, "projeto_negado"),
    ("5. ana emite reembolso dentro do limite", "ana", "emitir_reembolso",
     {"projeto_id": "proj-41", "valor": 450, "motivo": "curso"}, True, None),
    ("6. carla (admin) fecha o mês", "carla", "fechar_mes",
     {"mes": "2026-09"}, True, None),
]


def main() -> int:
    falhas = 0
    for desc, usuario, ferramenta, args, allow_ok, motivo in MATRIZ:
        r = httpx.post(
            f"{MCP}/tools/{ferramenta}",
            json=args,
            headers={"Authorization": f"Bearer {token(usuario)}"},
            timeout=5.0,
        )
        if allow_ok:
            ok = r.status_code == 200
        else:
            ok = r.status_code == 403 and motivo in r.json().get("detail", "")
        status = "✅" if ok else "❌"
        falhas += 0 if ok else 1
        print(f"{status} {desc} → HTTP {r.status_code} {r.json()}")
    print(f"\n{'TODOS OS CASOS OK' if falhas == 0 else f'{falhas} CASO(S) FALHARAM'}")
    return 1 if falhas else 0


if __name__ == "__main__":
    sys.exit(main())
