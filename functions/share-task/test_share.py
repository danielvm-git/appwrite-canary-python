from unittest.mock import MagicMock

import pytest

from share import ShareError, share_task


def setup(row=None):
    row = row or {}
    task = {
        "$id": "t1",
        "userId": "owner",
        "title": "Ship",
        "sharedWith": [],
        "sharedNames": [],
        "$permissions": ['read("user:owner")', 'update("user:owner")', 'delete("user:owner")'],
        **row,
    }
    db = MagicMock()
    db.get_row.return_value = task
    db.update_row.return_value = None
    people = {
        "ben@desk.dev": {"$id": "ben", "name": "Ben Lima", "email": "ben@desk.dev"},
        "owner@desk.dev": {"$id": "owner", "name": "Ana Souza", "email": "owner@desk.dev"},
    }
    find_user_by_email = MagicMock(side_effect=lambda email: people.get(email))
    return db, find_user_by_email, task


def expect_code_sync(fn, code):
    with pytest.raises(ShareError) as caught:
        fn()
    assert caught.value.code == code


def test_grants_read_and_update():
    db, find_user_by_email, _ = setup()
    result = share_task(
        caller_id="owner",
        task_id="t1",
        email=" Ben@Desk.dev ",
        db=db,
        find_user_by_email=find_user_by_email,
    )
    find_user_by_email.assert_called_with("ben@desk.dev")
    assert result == {"sharedWith": ["ben"], "sharedNames": ["Ben Lima"]}
    update = db.update_row.call_args.kwargs
    assert update["database_id"] == "todo"
    assert update["table_id"] == "tasks"
    assert update["row_id"] == "t1"
    perms = update["permissions"]
    assert 'read("user:ben")' in perms
    assert 'update("user:ben")' in perms
    assert 'delete("user:owner")' in perms
    assert 'delete("user:ben")' not in perms


def test_adds_owner_permissions_when_row_has_none():
    db, find_user_by_email, _ = setup({"$permissions": []})
    share_task(
        caller_id="owner",
        task_id="t1",
        email="ben@desk.dev",
        db=db,
        find_user_by_email=find_user_by_email,
    )
    perms = db.update_row.call_args.kwargs["permissions"]
    assert 'read("user:owner")' in perms
    assert 'update("user:owner")' in perms
    assert 'delete("user:owner")' in perms


def test_rejects_anonymous_callers():
    db, find_user_by_email, _ = setup()
    expect_code_sync(
        lambda: share_task(
            caller_id="",
            task_id="t1",
            email="ben@desk.dev",
            db=db,
            find_user_by_email=find_user_by_email,
        ),
        "unauthorized",
    )


def test_rejects_invalid_email_before_db():
    db, find_user_by_email, _ = setup()
    expect_code_sync(
        lambda: share_task(
            caller_id="owner",
            task_id="t1",
            email="ben",
            db=db,
            find_user_by_email=find_user_by_email,
        ),
        "invalid",
    )
    db.get_row.assert_not_called()


def test_only_owner_may_share():
    db, find_user_by_email, _ = setup()
    expect_code_sync(
        lambda: share_task(
            caller_id="ben",
            task_id="t1",
            email="owner@desk.dev",
            db=db,
            find_user_by_email=find_user_by_email,
        ),
        "forbidden",
    )
    db.update_row.assert_not_called()


def test_maps_missing_row_to_not_found():
    db, find_user_by_email, _ = setup()
    missing = Exception("Row not found")
    missing.code = 404  # type: ignore[attr-defined]
    db.get_row.side_effect = missing
    expect_code_sync(
        lambda: share_task(
            caller_id="owner",
            task_id="nope",
            email="ben@desk.dev",
            db=db,
            find_user_by_email=find_user_by_email,
        ),
        "not_found",
    )


def test_unknown_self_and_duplicate_invites():
    db_a, find_a, _ = setup()
    expect_code_sync(
        lambda: share_task(
            caller_id="owner",
            task_id="t1",
            email="zoe@desk.dev",
            db=db_a,
            find_user_by_email=find_a,
        ),
        "no_user",
    )

    db_b, find_b, _ = setup()
    expect_code_sync(
        lambda: share_task(
            caller_id="owner",
            task_id="t1",
            email="owner@desk.dev",
            db=db_b,
            find_user_by_email=find_b,
        ),
        "self",
    )

    db_c, find_c, _ = setup({"sharedWith": ["ben"], "sharedNames": ["Ben Lima"]})
    expect_code_sync(
        lambda: share_task(
            caller_id="owner",
            task_id="t1",
            email="ben@desk.dev",
            db=db_c,
            find_user_by_email=find_c,
        ),
        "already",
    )