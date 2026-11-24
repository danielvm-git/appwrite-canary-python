import json
import os

from appwrite.client import Client
from appwrite.query import Query
from appwrite.services.tables_db import TablesDB
from appwrite.services.users import Users

from share import ShareError, share_task


def _read_body(req):
    raw = getattr(req, "body", None) or getattr(req, "body_text", None) or ""
    if isinstance(raw, dict):
        return raw
    try:
        return json.loads(raw or "{}")
    except json.JSONDecodeError:
        return {}


class _Db:
    def __init__(self, tables_db: TablesDB) -> None:
        self._tables_db = tables_db

    def get_row(self, *, database_id: str, table_id: str, row_id: str):
        row = self._tables_db.get_row(
            database_id=database_id,
            table_id=table_id,
            row_id=row_id,
        )
        data = row.data
        if hasattr(data, "model_dump"):
            data = data.model_dump()
        elif not isinstance(data, dict):
            data = dict(data)
        perms = list(getattr(row, "permissions", None) or [])
        return {**data, "$permissions": perms}

    def update_row(self, *, database_id, table_id, row_id, data, permissions):
        self._tables_db.update_row(
            database_id=database_id,
            table_id=table_id,
            row_id=row_id,
            data=data,
            permissions=permissions,
        )


def main(context):
    if context.req.method != "POST":
        return context.res.json({"ok": False, "code": "method", "message": "Use POST."}, 405)

    client = (
        Client()
        .set_endpoint(os.environ["APPWRITE_FUNCTION_API_ENDPOINT"])
        .set_project(os.environ["APPWRITE_FUNCTION_PROJECT_ID"])
        .set_key(context.req.headers.get("x-appwrite-key") or "")
    )
    tables_db = TablesDB(client)
    users = Users(client)
    body = _read_body(context.req)
    caller_id = context.req.headers.get("x-appwrite-user-id") or ""

    def find_user_by_email(email: str):
        found = users.list(queries=[Query.equal("email", [email]), Query.limit(1)])
        user = found.users[0] if found.users else None
        if not user:
            return None
        return {"$id": user.id, "name": user.name, "email": user.email}

    try:
        result = share_task(
            caller_id=caller_id,
            task_id=body.get("taskId"),
            email=body.get("email"),
            db=_Db(tables_db),
            find_user_by_email=find_user_by_email,
        )
        context.log(
            json.dumps({"level": "info", "message": "task shared", "taskId": body.get("taskId")})
        )
        return context.res.json({"ok": True, **result})
    except ShareError as err:
        return context.res.json({"ok": False, "code": err.code, "message": err.message}, err.status)
    except Exception as err:
        context.error(
            json.dumps(
                {
                    "level": "error",
                    "message": "share failed",
                    "taskId": body.get("taskId"),
                    "err": str(err),
                }
            )
        )
        return context.res.json(
            {"ok": False, "code": "internal", "message": "Could not share the task."}, 500
        )