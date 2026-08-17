# Database Restore

Restoring the TaskFlow production database from a backup produced by
`scripts/backup-db.sh`.

Two situations are covered, and they are not the same operation:

- **verifying a backup**, against a throwaway container, with no impact on
  production. This is the routine case and should be run periodically.
- **restoring production**, after data loss or a failed migration. This
  destroys the current contents of the live database.

---

## Where backups live

`/home/mehdi/backups`, on the VPS disk, mode 700, owned by `mehdi`.

Two naming schemes coexist and must not be confused:

| Prefix | Origin | Pruned automatically |
|---|---|---|
| `taskflow-auto_` | `scripts/backup-db.sh`, daily | Yes, after 7 days |
| `taskflow_` | manual dumps taken by hand before risky operations | Never |

The retention logic matches on `taskflow-auto_*` only. A manual dump taken
before a migration is therefore safe from the timer, indefinitely.

**Backups sit on the same disk as the database.** This is a deliberate
trade-off, decided on 15 August 2026 and recorded in issue #17: it protects
against logical corruption, a bad migration or an accidental deletion, but not
against the loss of the server or its volume. An off-site copy was judged not
worth its recurring cost for this project.

---

## Verifying a backup

Run this against a disposable container. Production is never touched, and no
command in this section addresses `taskflow-db`.

### 1. Start a throwaway MySQL 8.4 container

```bash
export RESTORE_PWD="$(head -c 30 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32)"

docker run -d --name taskflow-restore-test \
  -e MYSQL_ROOT_PASSWORD="$RESTORE_PWD" \
  -e MYSQL_DATABASE=taskflow \
  mysql:8.4
```

The password exists only in this shell, for the lifetime of the test. No port is
published: the container is reachable from the Docker bridge and nowhere else.

### 2. Wait for the server to accept connections

```bash
until docker exec -e MYSQL_PWD="$RESTORE_PWD" taskflow-restore-test \
  mysqladmin ping -h 127.0.0.1 --silent 2>/dev/null; do sleep 2; done; echo "ready"
```

MySQL initialises its data directory on first start, which takes some seconds.
Polling is more reliable than a fixed `sleep`.

### 3. Load the most recent automated backup

```bash
LATEST="$(ls -1t /home/mehdi/backups/taskflow-auto_*.sql | head -1)"
echo "restoring: $LATEST"

docker exec -i -e MYSQL_PWD="$RESTORE_PWD" taskflow-restore-test \
  mysql -u root taskflow < "$LATEST" ; echo "exit=$?"
```

### 4. Compare row counts against production

```bash
docker exec -i -e MYSQL_PWD="$RESTORE_PWD" taskflow-restore-test \
  mysql -u root taskflow -N -e "SELECT 'users', COUNT(*) FROM users UNION ALL SELECT 'projects', COUNT(*) FROM projects UNION ALL SELECT 'tasks', COUNT(*) FROM tasks UNION ALL SELECT 'refresh_tokens', COUNT(*) FROM refresh_tokens UNION ALL SELECT 'user_providers', COUNT(*) FROM user_providers UNION ALL SELECT 'flyway', COUNT(*) FROM flyway_schema_history;"

read -rsp "taskflow password: " MYSQL_PWD; echo; export MYSQL_PWD

docker exec -i -e MYSQL_PWD taskflow-db \
  mysql -u taskflow taskflow -N -e "SELECT 'users', COUNT(*) FROM users UNION ALL SELECT 'projects', COUNT(*) FROM projects UNION ALL SELECT 'tasks', COUNT(*) FROM tasks UNION ALL SELECT 'refresh_tokens', COUNT(*) FROM refresh_tokens UNION ALL SELECT 'user_providers', COUNT(*) FROM user_providers UNION ALL SELECT 'flyway', COUNT(*) FROM flyway_schema_history;"
```

Use `COUNT(*)`, never `table_rows` from `information_schema`. The latter is an
InnoDB estimate and reports plainly wrong figures on small, freshly loaded
tables: during the 15 August 2026 test it showed 0 rows for `users` where the
real count was 16.

The two outputs must match line for line. Row counts drift if the database is
written to between the dump and the comparison, which is expected on a live
system; on this project it does not happen in practice.

### 5. Destroy the test container

```bash
docker rm -f -v taskflow-restore-test
unset MYSQL_PWD RESTORE_PWD LATEST
env | grep -cE 'MYSQL_PWD|RESTORE_PWD'
```

`-v` removes the anonymous volume along with the container. Without it, a full
copy of the database is left behind on disk, unmanaged and unnoticed.

The last command must print `0`.

---

## Restoring production

**This destroys the current contents of the live database.** Read the whole
section before running anything.

Restoring is the wrong first move in most incidents. If the API cannot
authenticate, if a container will not start, if a healthcheck is red, the
database itself is almost certainly intact and restoring will only add data loss
to the existing problem. Restore when the data is wrong, not when a service is.

### 1. Take a fresh manual dump first

Even damaged, the current state may hold rows the backup does not. See step 1 of
`DATABASE_CREDENTIAL_ROTATION.md`. Use the `taskflow_` prefix so the timer never
prunes it.

### 2. Stop the API

```bash
cd /opt/taskflow
docker compose stop taskflow-api
```

**This interrupts the service.** The API must not write while the schema is
being replaced. `taskflow-ui` stays up and serves a non-functional interface.

### 3. Choose and verify the backup

```bash
ls -lt /home/mehdi/backups/
tail -1 /home/mehdi/backups/<chosen-file>.sql
```

The last line of a complete dump is `-- Dump completed on ...`. If it is
missing, the file is truncated: pick another one.

Check which schema version it carries. A dump predating a migration will not
match the application's expectations, and Flyway will refuse to run against it.

```bash
grep -A3 'INSERT INTO `flyway_schema_history`' /home/mehdi/backups/<chosen-file>.sql | head -20
```

### 4. Load it

```bash
read -rsp "taskflow password: " MYSQL_PWD; echo; export MYSQL_PWD

docker exec -i -e MYSQL_PWD taskflow-db \
  mysql -u taskflow taskflow < /home/mehdi/backups/<chosen-file>.sql ; echo "exit=$?"
```

The dump contains `DROP TABLE IF EXISTS` before each `CREATE TABLE`, so existing
tables are replaced. Rows written since the backup are gone, permanently.

### 5. Restart and verify

```bash
docker compose start taskflow-api
docker compose ps
docker compose logs taskflow-api --tail=80 | grep -iE 'hikari|flyway|error|denied'
```

`HikariPool-1 - Added connection` proves the pool reconnected. Flyway must
report the schema as up to date, not attempt a migration.

Then log in through the web interface and load a real list. That is the only
check covering an end-to-end application read.

### 6. Clean up

```bash
unset MYSQL_PWD
history -c
history -w
```

---

## Known pitfalls

| Symptom | Cause | Fix |
|---|---|---|
| `table_rows` reports 0 on a table that has data | `information_schema` returns an InnoDB estimate | Use `COUNT(*)` |
| Flyway attempts to migrate after a restore | The dump predates the current schema version | Restore a dump matching the deployed version, or accept the migration knowingly |
| The restore appears to succeed but the API still fails | The API was never stopped and held stale connections | Stop the API before loading, restart after |
| Disk fills up after repeated verification tests | Test containers destroyed without `-v` leave their volumes behind | `docker rm -f -v`, then `docker volume prune` |
| `ERROR 1045 (28000): Access denied` during a restore | `MYSQL_PWD` holds the wrong account's password | Reload it with the current application password |

---

## Related

- `DATABASE_CREDENTIAL_ROTATION.md` — rotating the MySQL passwords
- `scripts/backup-db.sh` — the backup script itself
- `systemd/taskflow-backup.timer` — the daily schedule