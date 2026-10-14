"""Google Cloud Translation client (replaces Azure Translator), HTTP mocked."""

import json
import re

import httpx
import pytest
from fastapi import HTTPException

from app.services import translation_service as ts

PROJECT = "corestream-project"


@pytest.fixture
def google(monkeypatch):
    """Fake credentials + a programmable Cloud Translation endpoint."""
    calls: list[httpx.Request] = []
    state = {"handler": None}

    def default_handler(request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content)
        text = body["contents"][0]
        return httpx.Response(200, json={"translations": [{"translatedText": text.upper()}]})

    def transport(request: httpx.Request) -> httpx.Response:
        calls.append(request)
        return (state["handler"] or default_handler)(request)

    real_client = httpx.AsyncClient
    monkeypatch.setattr(
        ts.httpx, "AsyncClient",
        lambda **kw: real_client(transport=httpx.MockTransport(transport), **kw),
    )
    monkeypatch.setattr(ts, "_access_token_sync", lambda: ("ya29.fake", PROJECT))
    return calls, state


async def test_llama_a_translate_text_v3_con_el_token_de_la_cuenta(google):
    calls, _ = google
    assert await ts.translate_text("hola", "auto", "en") == "HOLA"

    req = calls[0]
    assert str(req.url) == (
        f"https://translation.googleapis.com/v3/projects/{PROJECT}/locations/global:translateText"
    )
    assert req.headers["Authorization"] == "Bearer ya29.fake"
    assert "x-goog-user-project" not in req.headers
    body = json.loads(req.content)
    assert body == {"contents": ["hola"], "targetLanguageCode": "en", "mimeType": "text/plain"}


async def test_idioma_origen_explicito_y_alias_de_chino(google):
    calls, _ = google
    await ts.translate_text("hola", "es", "zh")
    body = json.loads(calls[0].content)
    assert body["sourceLanguageCode"] == "es"
    assert body["targetLanguageCode"] == "zh-CN"


async def test_textos_largos_se_parten_en_fragmentos(google):
    calls, _ = google
    texto = ("línea de prueba\n" * 600)  # ~9.600 caracteres
    out = await ts.translate_long_text(texto, "auto", "en")
    assert out == texto.upper()
    assert len(calls) == 3
    assert all(len(json.loads(c.content)["contents"][0]) <= 4000 for c in calls)


async def test_lotes_html_para_docx_y_pdf(google):
    calls, state = google

    def html_handler(request):
        # Like Google: keeps the <p> tags (here with an attribute added) and
        # translates only the text between them.
        body = json.loads(request.content)
        assert body["mimeType"] == "text/html"
        out = re.sub(
            r"<p>(.*?)</p>", lambda m: f'<p dir="ltr">{m.group(1).upper()}</p>', body["contents"][0]
        )
        return httpx.Response(200, json={"translations": [{"translatedText": out}]})

    state["handler"] = html_handler
    out = await ts._translate_batch(["uno", "", "dos & tres"], "en")
    assert out == ["UNO", "", "DOS & TRES"]
    assert len(calls) == 1


async def test_json_traduce_solo_valores(google, tmp_path):
    f = tmp_path / "datos.json"
    f.write_text(json.dumps({"titulo": "hola", "n": 3, "items": ["a", ""]}), encoding="utf-8")
    content, name, mime = await ts.create_translated_file(str(f), "application/json", "datos.json", "en")
    assert json.loads(content) == {"titulo": "HOLA", "n": 3, "items": ["A", ""]}
    assert name == "datos_en.json" and mime == "application/json"


@pytest.mark.parametrize(
    "code, expected_status, fragment",
    [
        (400, 400, "idioma no soportado"),
        (403, 502, "roles/cloudtranslate.user"),
        (429, 503, "Límite de uso"),
        (500, 502, "(500)"),
    ],
)
async def test_errores_de_google_se_traducen_a_mensajes_claros(google, code, expected_status, fragment):
    _, state = google
    state["handler"] = lambda request: httpx.Response(code, text="secreto interno de google")
    with pytest.raises(HTTPException) as exc:
        await ts.translate_text("hola", "auto", "en")
    assert exc.value.status_code == expected_status
    assert fragment in exc.value.detail
    assert "secreto interno" not in exc.value.detail


async def test_caida_de_red(google):
    _, state = google

    def boom(request):
        raise httpx.ConnectError("sin red")

    state["handler"] = boom
    with pytest.raises(HTTPException) as exc:
        await ts.translate_text("hola", "auto", "en")
    assert exc.value.status_code == 503


def test_sin_credenciales_de_google_responde_no_configurada(monkeypatch):
    import google.auth
    from google.auth.exceptions import DefaultCredentialsError

    def no_creds(**kwargs):
        raise DefaultCredentialsError("no ADC")

    monkeypatch.setattr(ts, "_credentials", None)
    monkeypatch.setattr(google.auth, "default", no_creds)
    with pytest.raises(HTTPException) as exc:
        ts._access_token_sync()
    assert exc.value.status_code == 503
    assert "no está configurada" in exc.value.detail


def test_usa_el_proyecto_de_la_configuracion(monkeypatch):
    class Creds:
        valid = True
        token = "ya29.real"

    monkeypatch.setattr(ts, "_credentials", Creds())
    monkeypatch.setattr(ts, "_credentials_project", "otro-proyecto")
    monkeypatch.setattr(ts.get_settings(), "GCP_PROJECT_ID", PROJECT)
    assert ts._access_token_sync() == ("ya29.real", PROJECT)
