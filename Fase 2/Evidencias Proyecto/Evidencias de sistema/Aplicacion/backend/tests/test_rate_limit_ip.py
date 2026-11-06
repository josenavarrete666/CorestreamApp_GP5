"""Client IP resolution used by the login rate limiter."""

from starlette.requests import Request

from app.middleware.rate_limit import _client_ip


def _request(xff: str | None = None, peer: str = "10.0.0.9") -> Request:
    headers = [(b"x-forwarded-for", xff.encode())] if xff is not None else []
    return Request({"type": "http", "headers": headers, "client": (peer, 1234)})


def test_sin_proxy_usa_el_peer():
    assert _client_ip(_request("1.1.1.1"), xff_position=0) == "10.0.0.9"


def test_un_proxy_toma_la_ultima_entrada():
    assert _client_ip(_request("6.6.6.6, 200.1.2.3"), xff_position=1) == "200.1.2.3"


def test_balanceador_gcp_toma_la_penultima():
    req = _request("6.6.6.6, 200.1.2.3, 34.120.0.1")
    assert _client_ip(req, xff_position=2) == "200.1.2.3"


def test_cabecera_falseada_por_el_cliente_no_cambia_la_ip():
    # An attacker rotating the leftmost value must keep hitting the same key.
    a = _client_ip(_request("1.1.1.1, 200.1.2.3, 34.120.0.1"), xff_position=2)
    b = _client_ip(_request("9.9.9.9, 200.1.2.3, 34.120.0.1"), xff_position=2)
    assert a == b == "200.1.2.3"


def test_cabecera_ausente_o_corta_cae_al_peer():
    assert _client_ip(_request(None), xff_position=2) == "10.0.0.9"
    assert _client_ip(_request("200.1.2.3"), xff_position=2) == "10.0.0.9"


def test_valor_no_ip_cae_al_peer():
    req = _request("x" * 500 + ", 34.120.0.1")
    assert _client_ip(req, xff_position=2) == "10.0.0.9"


def test_ipv6_se_normaliza():
    req = _request("2001:DB8::1, 34.120.0.1")
    assert _client_ip(req, xff_position=2) == "2001:db8::1"
