"""
Documentos: subida y descarga con URLs firmadas (migración a GCP, plan D10).

Los tests corren con STORAGE_BACKEND=local (el default), que imita las URLs
firmadas de Cloud Storage con endpoints /api/documents/local-storage/{token}.
El flujo que ejercitan es el mismo que el del navegador contra GCS:
upload-url → PUT al almacenamiento → confirm; download-url → GET.
"""

import pytest

pytestmark = pytest.mark.asyncio(loop_scope="session")


async def _pedir_url(client, headers, nombre, contenido, ct="text/plain", **destino):
    return await client.post(
        "/api/documents/upload-url",
        json={"filename": nombre, "size": len(contenido), "content_type": ct, **destino},
        headers=headers,
    )


async def _subir(client, headers, nombre, contenido, ct="text/plain", **destino):
    """Los tres pasos del navegador. Devuelve la respuesta de /confirm."""
    res = await _pedir_url(client, headers, nombre, contenido, ct, **destino)
    assert res.status_code == 200, res.text[:300]
    firma = res.json()
    assert firma["method"] == "PUT"

    # Sin cabecera Authorization: la URL firmada es la única credencial.
    put = await client.put(firma["url"], content=contenido, headers=firma["headers"])
    assert put.status_code == 200, put.text[:300]

    return await client.post(
        "/api/documents/confirm", json={"upload_token": firma["upload_token"]}, headers=headers
    )


async def _descargar(client, headers, doc_id):
    res = await client.get(f"/api/documents/{doc_id}/download-url", headers=headers)
    assert res.status_code == 200, res.text[:300]
    return await client.get(res.json()["url"])


# ---------------------------------------------------------------------------
# Flujo completo
# ---------------------------------------------------------------------------

async def test_subir_y_descargar_documento(client, dev_headers, ticket, epic):
    res = await _subir(
        client, dev_headers, "notas.txt", b"contenido de prueba",
        ticket_id=ticket["id"], epic_id=epic["id"], doc_type="OTHER",
    )
    assert res.status_code == 201, res.text[:300]
    doc = res.json()
    assert doc["filename"] == "notas.txt"
    assert doc["file_size"] == len(b"contenido de prueba")
    assert doc["doc_type"] == "DOCUMENTATION"

    archivo = await _descargar(client, dev_headers, doc["id"])
    assert archivo.status_code == 200
    assert archivo.content == b"contenido de prueba"
    assert "attachment" in archivo.headers["content-disposition"]
    assert "notas.txt" in archivo.headers["content-disposition"]


async def test_acepta_los_nombres_de_campo_del_frontend(client, dev_headers, ticket):
    res = await _subir(client, dev_headers, "camel.txt", b"x", ticketId=ticket["id"], docType="CODE")
    assert res.status_code == 201
    assert res.json()["doc_type"] == "CODE"


async def test_nombre_con_acentos_se_descarga_intacto(client, dev_headers, ticket):
    res = await _subir(client, dev_headers, "diseño técnico.md", b"# hola", ticket_id=ticket["id"])
    archivo = await _descargar(client, dev_headers, res.json()["id"])
    assert "dise%C3%B1o%20t%C3%A9cnico.md" in archivo.headers["content-disposition"]


async def test_listar_documentos_de_un_ticket(client, dev_headers, ticket):
    await _subir(client, dev_headers, "a.txt", b"x", ticket_id=ticket["id"])
    res = await client.get(
        "/api/documents/", params={"ticketId": ticket["id"]}, headers=dev_headers
    )
    assert res.status_code == 200
    assert len(res.json()) >= 1


async def test_nombres_repetidos_se_numeran(client, dev_headers, ticket):
    a = await _subir(client, dev_headers, "repetido.txt", b"1", ticket_id=ticket["id"])
    b = await _subir(client, dev_headers, "repetido.txt", b"2", ticket_id=ticket["id"])
    assert a.json()["filename"] == "repetido.txt"
    assert b.json()["filename"] == "repetido (1).txt"


async def test_borrar_documento_elimina_el_objeto(client, dev_headers, ticket):
    res = await _subir(client, dev_headers, "borrable.txt", b"x", ticket_id=ticket["id"])
    doc_id = res.json()["id"]

    url = (await client.get(f"/api/documents/{doc_id}/download-url", headers=dev_headers)).json()["url"]

    res = await client.delete(f"/api/documents/{doc_id}", headers=dev_headers)
    assert res.status_code in (200, 204)

    assert (await client.get(url)).status_code == 404
    assert (await client.get(f"/api/documents/{doc_id}/download-url", headers=dev_headers)).status_code == 404


async def test_traducir_lee_el_archivo_del_almacenamiento(client, dev_headers, ticket, monkeypatch):
    import app.routers.documents as documents_router

    async def falso(texto, origen, destino):
        return f"[{destino}] {texto}"

    monkeypatch.setattr(documents_router, "translate_long_text", falso)
    res = await _subir(client, dev_headers, "traducir.txt", b"hola mundo", ticket_id=ticket["id"])

    res = await client.post(
        f"/api/documents/{res.json()['id']}/translate",
        json={"target_language": "en"},
        headers=dev_headers,
    )
    assert res.status_code == 200, res.text[:300]
    assert res.json()["translated_text"] == "[en] hola mundo"


# ---------------------------------------------------------------------------
# Validaciones al pedir la URL
# ---------------------------------------------------------------------------

async def test_rechaza_extension_no_permitida(client, dev_headers, ticket):
    res = await _pedir_url(client, dev_headers, "malicioso.sh", b"#!/bin/sh", ticket_id=ticket["id"])
    assert res.status_code == 400


async def test_sanea_el_path_traversal_en_el_nombre(client, dev_headers, ticket):
    """El nombre debe quedar reducido al fichero, sin componentes de ruta."""
    res = await _subir(client, dev_headers, "../../../../tmp/escapado.txt", b"x", ticket_id=ticket["id"])
    assert res.status_code == 201
    nombre = res.json()["filename"]
    assert "/" not in nombre and ".." not in nombre
    assert nombre == "escapado.txt"


async def test_rechaza_ficheros_demasiado_grandes(client, dev_headers, ticket):
    res = await client.post(
        "/api/documents/upload-url",
        json={"filename": "enorme.txt", "size": 60 * 1024 * 1024, "ticket_id": ticket["id"]},
        headers=dev_headers,
    )
    assert res.status_code == 413


async def test_el_almacenamiento_rechaza_mas_bytes_de_los_permitidos(client, dev_headers, ticket):
    """Declarar un tamaño chico y subir uno grande no sirve: el límite va firmado."""
    res = await _pedir_url(client, dev_headers, "mentira.txt", b"x", ticket_id=ticket["id"])
    firma = res.json()
    put = await client.put(firma["url"], content=b"A" * (26 * 1024 * 1024), headers=firma["headers"])
    assert put.status_code == 400

    res = await client.post(
        "/api/documents/confirm", json={"upload_token": firma["upload_token"]}, headers=dev_headers
    )
    assert res.status_code == 400


async def test_exige_epica_o_ticket(client, dev_headers):
    res = await _pedir_url(client, dev_headers, "huerfano.txt", b"x")
    assert res.status_code == 400


async def test_epica_inexistente(client, dev_headers):
    res = await _pedir_url(
        client, dev_headers, "x.txt", b"x", epic_id="00000000-0000-0000-0000-000000000000"
    )
    assert res.status_code == 404


# ---------------------------------------------------------------------------
# Confirmación
# ---------------------------------------------------------------------------

async def test_confirmar_sin_haber_subido(client, dev_headers, ticket):
    res = await _pedir_url(client, dev_headers, "fantasma.txt", b"x", ticket_id=ticket["id"])
    res = await client.post(
        "/api/documents/confirm", json={"upload_token": res.json()["upload_token"]}, headers=dev_headers
    )
    assert res.status_code == 400


async def test_un_usuario_no_confirma_la_subida_de_otro(client, dev_headers, dev2_headers, ticket):
    res = await _pedir_url(client, dev_headers, "ajeno.txt", b"x", ticket_id=ticket["id"])
    firma = res.json()
    await client.put(firma["url"], content=b"x", headers=firma["headers"])

    res = await client.post(
        "/api/documents/confirm", json={"upload_token": firma["upload_token"]}, headers=dev2_headers
    )
    assert res.status_code == 400


async def test_token_manipulado(client, dev_headers):
    res = await client.post(
        "/api/documents/confirm", json={"upload_token": "no.es.un-token"}, headers=dev_headers
    )
    assert res.status_code == 400


async def test_confirmar_dos_veces_no_duplica(client, dev_headers, ticket):
    res = await _pedir_url(client, dev_headers, "una-vez.txt", b"x", ticket_id=ticket["id"])
    firma = res.json()
    await client.put(firma["url"], content=b"x", headers=firma["headers"])
    body = {"upload_token": firma["upload_token"]}

    assert (await client.post("/api/documents/confirm", json=body, headers=dev_headers)).status_code == 201
    assert (await client.post("/api/documents/confirm", json=body, headers=dev_headers)).status_code == 400


# ---------------------------------------------------------------------------
# Acceso
# ---------------------------------------------------------------------------

async def test_pedir_urls_requiere_autenticacion(client, ticket):
    res = await client.post(
        "/api/documents/upload-url",
        json={"filename": "x.txt", "size": 1, "ticket_id": ticket["id"]},
    )
    assert res.status_code in (401, 403)


async def test_url_de_almacenamiento_falsa(client):
    assert (await client.get("/api/documents/local-storage/inventado")).status_code == 403
    assert (await client.put("/api/documents/local-storage/inventado", content=b"x")).status_code == 403


async def test_documento_sin_migrar_responde_410(client, dev_headers, ticket):
    """Filas con ruta de disco antigua (de antes de migrar a GCS) no rompen la API."""
    from sqlalchemy import update

    from app.database import get_session_maker
    from app.models import Document

    res = await _subir(client, dev_headers, "viejo.txt", b"x", ticket_id=ticket["id"])
    doc_id = res.json()["id"]
    async with get_session_maker()() as db:
        await db.execute(
            update(Document).where(Document.id == doc_id)
            .values(file_path="/app/storage/documents/20250101_viejo.txt")
        )
        await db.commit()

    res = await client.get(f"/api/documents/{doc_id}/download-url", headers=dev_headers)
    assert res.status_code == 410


async def test_script_de_migracion_sube_los_archivos_de_azure(client, dev_headers, ticket, tmp_path):
    """
    Simula un documento creado en Azure (ruta de disco en file_path) y corre
    app.scripts.migrate_documents_to_gcs contra el almacenamiento actual.
    """
    from sqlalchemy import update

    from app.database import get_session_maker
    from app.models import Document
    from app.scripts.migrate_documents_to_gcs import migrate
    from app.services.storage import get_storage

    res = await _subir(client, dev_headers, "de-azure.txt", b"temporal", ticket_id=ticket["id"])
    doc_id = res.json()["id"]
    (tmp_path / "20250101_120000000000_de-azure.txt").write_bytes(b"contenido original de azure")
    async with get_session_maker()() as db:
        await db.execute(
            update(Document).where(Document.id == doc_id)
            .values(file_path="/app/storage/documents/20250101_120000000000_de-azure.txt")
        )
        await db.commit()

    seco = await migrate(tmp_path, get_storage(), dry_run=True)
    assert seco["migrados"] >= 1
    assert (await client.get(f"/api/documents/{doc_id}/download-url", headers=dev_headers)).status_code == 410

    stats = await migrate(tmp_path, get_storage())
    assert stats["migrados"] >= 1

    archivo = await _descargar(client, dev_headers, doc_id)
    assert archivo.content == b"contenido original de azure"

    # Idempotente: una segunda pasada no vuelve a subir nada.
    assert (await migrate(tmp_path, get_storage()))["migrados"] == 0
