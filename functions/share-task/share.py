from __future__ import annotations

import re
from typing import Any, Callable, Dict, List

EMAIL = re.compile(r"^\S+@\S+\.\S+$")


class ShareError(Exception):
    def __init__(self, code: str, message: str, status: int = 400) -> None:
        self.code = code
        self.message = message
        self.status = status
        super().__init__(message)


def owner_permissions(user_id: str) -> List[str]:
    return [
        f'read("user:{user_id}")',
        f'update("user:{user_id}")',
        f'delete("user:{user_id}")',
    ]


def share_task(
    *,
    caller_id: str,
    task_id: str,
    email: str,
    db: Any,
    find_user_by_email: Callable[[str], Any],
    database_id: str = "todo",
    table_id: str = "tasks",
) -> Dict[str, List[str]]:
    if not caller_id:
        raise ShareError("unauthorized", "Sign in to share tasks.", 401)
    target = str(email or "").strip().lower()
    if not task_id:
        raise ShareError("invalid", "Missing task id.")
    if not EMAIL.match(target):
        raise ShareError("invalid", "Enter a valid email.")

    try:
        row = db.get_row(database_id=database_id, table_id=table_id, row_id=task_id)
    except Exception as err:
        if getattr(err, "code", None) == 404:
            raise ShareError("not_found", "Task not found.", 404) from err
        raise

    if row.get("userId") != caller_id:
        raise ShareError("forbidden", "Only the owner can share this task.", 403)

    user = find_user_by_email(target)
    if not user:
        raise ShareError("no_user", "No user with that email.", 404)
    if user.get("$id") == caller_id:
        raise ShareError("self", "That's you.")

    shared_with = list(row.get("sharedWith") or [])
    if user.get("$id") in shared_with:
        raise ShareError("already", "Already shared.", 409)

    next_with = [*shared_with, user["$id"]]
    next_names = [*list(row.get("sharedNames") or []), user.get("name") or target.split("@")[0]]
    permissions = list(
        dict.fromkeys(
            [
                *(row.get("$permissions") or []),
                *owner_permissions(row["userId"]),
                f'read("user:{user["$id"]}")',
                f'update("user:{user["$id"]}")',
            ]
        )
    )

    db.update_row(
        database_id=database_id,
        table_id=table_id,
        row_id=task_id,
        data={"sharedWith": next_with, "sharedNames": next_names},
        permissions=permissions,
    )
    return {"sharedWith": next_with, "sharedNames": next_names}