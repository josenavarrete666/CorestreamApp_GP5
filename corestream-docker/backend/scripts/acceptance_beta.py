"""Prepare and retire tracked beta acceptance data in Docker development."""

from __future__ import annotations

import argparse
import asyncio
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlparse
from uuid import UUID, uuid5

from sqlalchemy import delete, func, or_, select
from sqlalchemy.engine import make_url

from app.config import get_settings
from app.database import dispose_engine, get_session_maker
from app.models import Application, Base, Epic, Notification, Subtask, Ticket, TicketEvent, User
from app.models.incident import AffectedEnvironment, Incident, IncidentSeverity, IncidentStatus
from app.models.ticket import TicketPriority, TicketStatus, TicketType
from app.redis_client import close_redis, init_redis
from app.services.auth_service import AuthService
from app.services.notification_service import create_notification, publish_notification
from scripts.acceptance_stage8 import identifiers, save
from scripts.acceptance_stage8 import run as initial_run


def beta_identifiers(run_id: UUID) -> dict[str, str]:
    return {key: str(uuid5(run_id, f"beta:{key}")) for key in (
        "empty_application", "epic2", "unassigned", "progress", "blocked", "completed",
        "support", "subtask", "subtask2", "reported", "investigating", "mitigated", "resolved",
    )}


def guard() -> None:
    settings = get_settings()
    url = make_url(settings.DATABASE_URL)
    redis = urlparse(settings.REDIS_URL)
    if settings.ENVIRONMENT != "development" or url.host != "postgres" or url.database != "corestream":
        raise RuntimeError("Expected Docker development database corestream")
    if redis.hostname != "redis" or redis.path != "/0":
        raise RuntimeError("Expected Docker development Redis db 0")


async def run(action: str, run_id: UUID, path: Path, admin_file: Path | None = None) -> dict:
    guard()
    extra = beta_identifiers(run_id)
    prefix = f"Verification stage 8 - {run_id}"
    if action == "setup":
        if await asyncio.to_thread(path.exists):
            raise RuntimeError("Manifest already exists; no data overwritten")
        if admin_file is None:
            raise RuntimeError("Existing ADMIN manifest is required")
        source = json.loads(await asyncio.to_thread(admin_file.read_text, encoding="utf-8"))
        async with get_session_maker()() as db:
            admin = await db.get(User, UUID(source["admin_id"]))
            credentials = source["users"]["admin"]
            if not admin or admin.email != credentials["email"] or not AuthService.verify_password(credentials["password"], admin.hashed_password):
                raise RuntimeError("Existing ADMIN identity does not match")
        await initial_run("setup", run_id, path)
        data = json.loads(await asyncio.to_thread(path.read_text, encoding="utf-8"))
        if data["admin_id"] != source["admin_id"]:
            raise RuntimeError("ADMIN identity changed; stop before extending fixture")
        data["users"]["admin"] = credentials
        data["beta_ids"] = extra
        data["purpose"] = "beta-development"
        data["created_at"] = datetime.now(timezone.utc).isoformat()
        data["tracked_tickets"] = []
        await asyncio.to_thread(save, path, data)
        ids = data["ids"]
        async with get_session_maker()() as db:
            for key in ("developer", "leader", "other"):
                user = await db.get(User, UUID(ids[key]))
                if user is None:
                    raise RuntimeError("Fixture user missing")
                user.must_change_password = False
                user.full_name = {"developer": "Beta Desarrollador", "leader": "Beta Líder", "other": "Beta Colaborador"}[key]
            application = await db.get(Application, UUID(ids["application"]))
            if application is None:
                raise RuntimeError("Fixture application missing")
            application.name = prefix
            db.add(Application(id=UUID(extra["empty_application"]), name=f"{prefix} - Vacía", owner_id=UUID(data["admin_id"])))
            db.add(Epic(id=UUID(extra["epic2"]), application_id=application.id, title="Entrega y revisión", order_index=1))
            await db.flush()
            original = await db.get(Ticket, UUID(ids["ticket"]))
            if original is None:
                raise RuntimeError("Fixture ticket missing")
            original.title = "Implementar integración beta"
            original.description = "Recorrido real de asignación, trabajo, pregunta y finalización."
            original.priority = TicketPriority.HIGH
            now = datetime.now(timezone.utc)
            for index, (key, state, assignee) in enumerate((
                ("unassigned", TicketStatus.TODO, None),
                ("progress", TicketStatus.IN_PROGRESS, ids["developer"]),
                ("blocked", TicketStatus.BLOCKED_QUESTION, ids["other"]),
                ("completed", TicketStatus.COMPLETED, ids["developer"]),
            ), start=1):
                db.add(Ticket(id=UUID(extra[key]), title={
                    "unassigned": "Tarea disponible para reclamar", "progress": "Trabajo en progreso",
                    "blocked": "Pregunta pendiente del equipo", "completed": "Entrega completada",
                }[key], description="Dato local persistente de aceptación beta.",
                    epic_id=UUID(extra["epic2"] if key == "completed" else ids["epic"]),
                    assignee_id=UUID(assignee) if assignee else None, created_by_id=UUID(ids["leader"]),
                    status=state, priority=TicketPriority.MEDIUM, order_index=index,
                    time_spent_seconds=180 if key != "unassigned" else 0,
                    timer_started_at=now - timedelta(seconds=30) if key == "progress" else None,
                    block_reason="¿Cuál es el criterio de aceptación definitivo?" if key == "blocked" else None,
                    completed_at=now - timedelta(days=1) if key == "completed" else None,
                    due_date=now - timedelta(days=1) if key == "blocked" else None))
            db.add(Ticket(id=UUID(extra["support"]), title="Soporte separado de incidentes",
                ticket_type=TicketType.SUPPORT, status=TicketStatus.REPORTED,
                assignee_id=UUID(ids["other"]), created_by_id=UUID(ids["leader"])))
            await db.flush()
            for index, key in enumerate(("subtask", "subtask2")):
                db.add(Subtask(id=UUID(extra[key]), ticket_id=original.id,
                    title=("Verificar contrato HTTP", "Confirmar persistencia SQL")[index], order_index=index))
            for index, key in enumerate(("reported", "investigating", "mitigated", "resolved")):
                db.add(Incident(id=UUID(extra[key]), title=f"Incidente {key}",
                    description="Incidente real, no ticket SUPPORT.", application_id=application.id,
                    created_by_id=UUID(ids["leader"]), assigned_to_id=UUID(ids["developer"]) if index != 0 else None,
                    status=IncidentStatus(key.upper()), severity=(IncidentSeverity.P1, IncidentSeverity.P2, IncidentSeverity.P3, IncidentSeverity.P3)[index],
                    affected_environment=AffectedEnvironment.STAGING,
                    mitigation_state="Alternativa temporal aplicada" if key == "mitigated" else None))
            await db.commit()
    data = json.loads(await asyncio.to_thread(path.read_text, encoding="utf-8"))
    if data.get("purpose") != "beta-development" or data["run_id"] != str(run_id) or data["ids"] != identifiers(run_id) or data["beta_ids"] != extra:
        raise RuntimeError("Fixture identity mismatch")
    ids = data["ids"]
    async with get_session_maker()() as db:
        empty_app = await db.get(Application, UUID(extra["empty_application"]))
        if empty_app is None or empty_app.name != f"{prefix} - Vacía":
            raise RuntimeError("Fixture empty application missing or changed")
        for epic_id in (ids["epic"], extra["epic2"]):
            epic = await db.get(Epic, UUID(epic_id))
            if epic is None or str(epic.application_id) != ids["application"]:
                raise RuntimeError("Fixture epic relationship changed")
        for key in ("application",):
            item = await db.get(Application, UUID(ids[key]))
            if item is None or item.name != prefix:
                raise RuntimeError("Fixture application missing or changed")
        for key in ("leader", "developer", "other", "inactive"):
            user = await db.get(User, UUID(ids[key]))
            if user is None or user.email != data["users"][key]["email"]:
                raise RuntimeError("Fixture user missing or changed")
        ticket_ids = [UUID(ids["ticket"]), *(UUID(extra[k]) for k in ("unassigned", "progress", "blocked", "completed", "support")),
                      *(UUID(value) for value in data["tracked_tickets"])]
        tickets = (await db.execute(select(Ticket).where(Ticket.id.in_(ticket_ids)))).scalars().all()
        if len(tickets) != len(ticket_ids):
            raise RuntimeError("Fixture tickets missing")
        for ticket in tickets:
            if str(ticket.id) == extra["support"]:
                if ticket.ticket_type != TicketType.SUPPORT or ticket.epic_id is not None:
                    raise RuntimeError("Fixture support ticket changed")
            elif ticket.ticket_type != TicketType.DEVELOPMENT or str(ticket.epic_id) not in (ids["epic"], extra["epic2"]):
                raise RuntimeError("Fixture ticket relationship changed")
        incidents = (await db.execute(select(Incident).where(Incident.id.in_([UUID(extra[k]) for k in ("reported", "investigating", "mitigated", "resolved")])))).scalars().all()
        if len(incidents) != 4:
            raise RuntimeError("Fixture incidents missing")
        if action == "support-event":
            notification = await create_notification(db, user_id=ids["developer"], title=prefix,
                message="Notificación de soporte: dominio separado", notification_type="SYSTEM", ticket_id=extra["support"])
            await db.commit()
            await db.refresh(notification)
            data["notifications"].append(str(notification.id))
            await asyncio.to_thread(save, path, data)
            await init_redis()
            try:
                published = await publish_notification(notification)
            finally:
                await close_redis()
            return {"run_id": str(run_id), "notification_id": str(notification.id), "published": published}
        result = {"run_id": str(run_id), "admin_id": data["admin_id"], "ids": ids, "beta_ids": extra,
                  "verified": True, "tickets": [{"id": str(t.id), "status": t.status.value,
                      "assignee_id": str(t.assignee_id) if t.assignee_id else None,
                      "time_spent_seconds": t.time_spent_seconds, "timer_running": t.timer_started_at is not None,
                      "completed_at": t.completed_at.isoformat() if t.completed_at else None} for t in tickets],
                   "incidents": [{"id": str(i.id), "status": i.status.value} for i in incidents]}
        result["subtasks"] = [{"id": str(s.id), "ticket_id": str(s.ticket_id), "is_completed": s.is_completed}
                              for s in (await db.execute(select(Subtask).where(Subtask.ticket_id.in_(ticket_ids)))).scalars()]
        result["events"] = [{"id": str(e.id), "ticket_id": str(e.ticket_id), "type": e.event_type.value}
                            for e in (await db.execute(select(TicketEvent).where(TicketEvent.ticket_id.in_(ticket_ids))
                                                       .order_by(TicketEvent.created_at))).scalars()]
        result["notifications"] = [{"id": str(n.id), "user_id": str(n.user_id), "is_read": n.is_read}
                                   for n in (await db.execute(select(Notification).where(or_(
                                       Notification.id.in_([UUID(v) for v in data["notifications"]]),
                                       Notification.ticket_id.in_(ticket_ids))))).scalars()]
        if action == "cleanup":
            notifications = (await db.execute(select(Notification).where(or_(
                Notification.id.in_([UUID(v) for v in data["notifications"]]), Notification.ticket_id.in_(ticket_ids))))).scalars().all()
            owned = {
                "users": [UUID(ids[k]) for k in ("leader", "developer", "other", "inactive")],
                "applications": [UUID(ids["application"]), UUID(extra["empty_application"])],
                "epics": [UUID(ids["epic"]), UUID(extra["epic2"])], "tickets": ticket_ids,
                "subtasks": list((await db.execute(select(Subtask.id).where(Subtask.ticket_id.in_(ticket_ids)))).scalars()),
                "ticket_events": list((await db.execute(select(TicketEvent.id).where(TicketEvent.ticket_id.in_(ticket_ids)))).scalars()),
                "incidents": [i.id for i in incidents], "notifications": [n.id for n in notifications],
            }
            for table in Base.metadata.sorted_tables:
                references = [column.in_(owned[fk.column.table.name]) for column in table.columns
                              for fk in column.foreign_keys if fk.column.table.name in owned]
                if references:
                    statement = select(func.count()).select_from(table).where(or_(*references))
                    if table.name in owned:
                        statement = statement.where(table.c.id.not_in(owned[table.name]))
                    if (await db.execute(statement)).scalar_one():
                        raise RuntimeError(f"Untracked references in {table.name}; cleanup aborted")
            for table in reversed(Base.metadata.sorted_tables):
                if table.name in owned:
                    await db.execute(delete(table).where(table.c.id.in_(owned[table.name])))
            await db.commit()
            result["removed"] = True
        return result


async def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("setup", "check", "cleanup", "support-event"))
    parser.add_argument("run_id", type=UUID)
    parser.add_argument("--local-file", required=True, type=Path)
    parser.add_argument("--admin-file", type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(await run(args.action, args.run_id, args.local_file, args.admin_file), indent=2))
    finally:
        await dispose_engine()


if __name__ == "__main__":
    asyncio.run(main())
