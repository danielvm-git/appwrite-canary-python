# AGENTS — appwrite-canary-python

| Action | Command |
|--------|---------|
| Setup | `npm ci` |
| Preflight | `bash scripts/preflight.sh` |
| Dev | `npm run dev` |
| Build | `npm run build` |
| Deploy share function | `bash scripts/deploy-share-function.sh` (reads `../.env.provision`; site CI does not deploy it) |

Sharing runs in the Appwrite Function `share-task-python` (`functions/share-task`): browsers cannot look up users or grant `user:<id>` permissions, so the function does both with its dynamic server key.

Shell sync: `bash ../appwrite-canary-shell/scripts/sync-shell.sh .`

## Observability

| What | Command |
|------|---------|
| Production health | `curl -s https://python.danielvm.net/health.json` |
| Smoke + schema | `bash scripts/observability-check.sh` |
| TablesDB isolation + sharing | `bash scripts/verify-todo-live.sh` |
| Share function logs | Appwrite Console → Functions → **Share task (Python)** → Executions |
| Function unit tests | `bash scripts/verify-story-e09s02.sh` |