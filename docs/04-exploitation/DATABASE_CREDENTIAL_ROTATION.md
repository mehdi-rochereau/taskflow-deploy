# Database Credential Rotation

Rotating the MySQL passwords of the TaskFlow production stack.

Applies to three accounts: `taskflow@'%'` (application account, carried by
`DB_PASSWORD`), `root@localhost` and `root@'%'` (both carried by
`MYSQL_ROOT_PASSWORD` in `/opt/taskflow/.env`).

---

## When to run this

- A password has been displayed, logged, or otherwise exposed.
- A password has been shared, deliberately or not.
- Scheduled rotation.

---

## The ordering constraint

**This is not negotiable.**

`MYSQL_USER` and `MYSQL_PASSWORD` are read by the MySQL image **only when the
data volume is first initialised**. The `taskflow-db-data` volume has been
initialised since the first deployment. Editing `.env` and restarting the stack
therefore changes nothing on the server: the credentials stored in the `mysql`
system schema stay as they are, and the API simply fails to authenticate.

The correct order is:

1. `ALTER USER` against the **running** server
2. then `/opt/taskflow/.env`
3. then container recreation

Any other order breaks the API's connection to the database.

---

## Before you start

Generate the new passwords in your password manager **before** touching the
server, and store them there first. Use:

- 40 characters, alphanumeric, random
- **no special characters**

Special characters are excluded on purpose. `$`, quotes, backslash and backtick
all carry meaning in at least one of the three contexts these values travel
through: the shell, the `.env` file read by Docker Compose, and SQL statements.
A value containing them works until the day it does not, with an error message
that points nowhere near the real cause. 40 alphanumeric characters carry about
238 bits of entropy, which is far beyond what is needed here.

Generating in the password manager rather than on the server also removes the
need to ever read a live password back off production. That read is what causes
exposure incidents in the first place.

---

## Never expose a value

Throughout this procedure:

- `read -rsp` for every password entry. `-s` suppresses the echo, so nothing
  appears on screen, in the shell history, or in the process table.
- `MYSQL_PWD` as an environment variable, never `-p<value>` on the command line.
  Command-line arguments are world-readable in `/proc` for as long as the
  process lives.
- `docker exec -i -e VAR container ...` passes the variable **by name**. The
  value is inherited from your shell and never written into the command line.
- For `ALTER USER`, pipe the statement through stdin rather than passing it with
  `-e "..."`. Your shell expands `$VAR` before `docker` is invoked, so `-e` puts
  the plaintext password into the `docker` process arguments.
- Never use an interactive password prompt through `docker compose exec -T`.
  Without a TTY, the prompt cannot suppress the echo.

---

## Procedure

All commands run on the VPS over SSH, as user `mehdi`, unless stated otherwise.

### 1. Take a manual dump

```bash
cd /opt/taskflow
read -rsp "Current taskflow password: " MYSQL_PWD; echo; export MYSQL_PWD

mkdir -p /home/mehdi/backups
chmod 700 /home/mehdi/backups
STAMP=$(date -u +%Y%m%dT%H%M%SZ)

docker exec -i -e MYSQL_PWD taskflow-db \
  mysqldump -u taskflow --single-transaction --no-tablespaces \
  --routines --triggers --events taskflow \
  > "/home/mehdi/backups/taskflow_${STAMP}.sql"

chmod 600 "/home/mehdi/backups/taskflow_${STAMP}.sql"
```

`--single-transaction` dumps inside one transaction, without locking tables, so
production keeps serving. `--no-tablespaces` skips the InnoDB tablespace listing,
which requires the server-wide `PROCESS` privilege the application account does
not have and must not be granted. `--routines --triggers --events` include stored
procedures, triggers and scheduled events, all of which `mysqldump` omits by
default: a dump without them looks complete and is not.

Verify the dump before going any further:

```bash
tail -1 "/home/mehdi/backups/taskflow_${STAMP}.sql"
grep -c "^CREATE TABLE" "/home/mehdi/backups/taskflow_${STAMP}.sql"

docker exec -i -e MYSQL_PWD taskflow-db \
  mysql -u taskflow -N -e \
  "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='taskflow';"
```

The last line of a complete dump is `-- Dump completed on ...`. If it is missing,
the dump was truncated: **stop here**. The two table counts must match.

### 2. Rotate the application account

```bash
read -rsp "Current ROOT password: " MYSQL_PWD; echo; export MYSQL_PWD
read -rsp "NEW taskflow password: " NEW_APP_PWD; echo

printf "ALTER USER 'taskflow'@'%%' IDENTIFIED BY '%s';\n" "$NEW_APP_PWD" \
  | docker exec -i -e MYSQL_PWD taskflow-db mysql -u root
```

`%%` in the `printf` format produces a single `%`, since `printf` treats the
percent sign as an escape character.

From this statement on, the API can no longer open new connections. Existing
pooled connections keep working for a while, so the service does not fall over
immediately, but the window is open. Do not pause here.

Verify both directions:

```bash
docker exec -i -e MYSQL_PWD="$NEW_APP_PWD" taskflow-db \
  mysql -u taskflow -N -e "SELECT 'new app password OK';"

read -rsp "OLD taskflow password: " OLD_APP_PWD; echo
docker exec -i -e MYSQL_PWD="$OLD_APP_PWD" taskflow-db \
  mysql -u taskflow -N -e "SELECT 1;" ; echo "exit=$?"
```

The second must fail with error 1045 and a non-zero exit code.

### 3. Rotate both root accounts

`root@localhost` and `root@'%'` are **two distinct accounts** with separate
passwords. In MySQL an account is a name/host pair, and `%` is a wildcard
matching any host. Connections through the Unix socket authenticate as
`root@localhost`; connections over TCP, including from other containers,
authenticate as `root@'%'`.

```bash
read -rsp "NEW root@localhost password: " NEW_ROOT_LOCAL_PWD; echo

printf "ALTER USER 'root'@'localhost' IDENTIFIED BY '%s';\n" "$NEW_ROOT_LOCAL_PWD" \
  | docker exec -i -e MYSQL_PWD taskflow-db mysql -u root
```

`MYSQL_PWD` still holds the **old** root password here, which is what
authenticates this statement.

```bash
read -rsp "NEW root@% password: " NEW_ROOT_ANY_PWD; echo

printf "ALTER USER 'root'@'%%' IDENTIFIED BY '%s';\n" "$NEW_ROOT_ANY_PWD" \
  | docker exec -i -e MYSQL_PWD="$NEW_ROOT_LOCAL_PWD" taskflow-db mysql -u root
```

Note the change: the statement above travels through the Unix socket, so it
authenticates as `root@localhost`, whose password has just changed. Reusing the
old value here fails.

### 4. Record the start of the outage window

```bash
date -u +'%Y-%m-%dT%H:%M:%SZ'
```

### 5. Update the environment file

```bash
nano /opt/taskflow/.env
chmod 600 /opt/taskflow/.env
```

Two lines change: `MYSQL_ROOT_PASSWORD` and `DB_PASSWORD`.

`MYSQL_ROOT_PASSWORD` takes the **`root@'%'`** value. The `root@localhost` value
lives in the password manager only, and is typed at the prompt when opening a
client. Getting this backwards is not harmless while the old healthcheck is still
deployed: it pings over TCP, so it authenticates `root@'%'`, and a mismatch keeps
`taskflow-db` `unhealthy`, which in turn blocks `taskflow-api` through
`condition: service_healthy`.

`chmod 600` is mandatory after any edit. Editors do not preserve permissions.

Validate before recreating:

```bash
cd /opt/taskflow
docker compose config --quiet ; echo "exit=$?"
```

### 6. Recreate the containers

**This interrupts the service.**

```bash
docker compose up -d
```

Compose detects the environment change and recreates `taskflow-db` and
`taskflow-api`. `taskflow-ui` is untouched: it stays up but serves a
non-functional interface until the API is back.

### 7. Record the end of the outage window

```bash
date -u +'%Y-%m-%dT%H:%M:%SZ'
```

### 8. Verification

```bash
docker compose ps

curl -s https://api.taskflow.mehdi-rochereau.dev/actuator/health

docker compose logs taskflow-api --tail=80 | grep -iE 'hikari|flyway|error|denied'
```

Both healthchecks must read `healthy`. `taskflow-api` has a 60-second
`start_period`, so allow time before concluding.

`{"status":"UP"}` alone does not prove the database connection: Spring Boot hides
component detail by default. The proof is in the logs, where
`HikariPool-1 - Added connection` shows the pool established itself with the new
password, and no `Access denied` appears.

Finally, log in through the web interface and load a real list. That is the only
check covering an end-to-end application read.

### 9. Clean up

```bash
unset MYSQL_PWD NEW_APP_PWD OLD_APP_PWD NEW_ROOT_LOCAL_PWD NEW_ROOT_ANY_PWD STAMP
env | grep -cE 'MYSQL_PWD|_APP_PWD|_ROOT_.*_PWD'

grep -nE '\-p[^ ]|PASSWORD=|IDENTIFIED BY' ~/.bash_history | cut -c1-80
history | grep -nE '\-p[^ ]|PASSWORD=|IDENTIFIED BY' | cut -c1-100

docker compose logs taskflow-db --tail=200 | grep -icE 'password|denied'

history -c
history -w
```

Bash writes the current session's commands to `~/.bash_history` only on logout,
so the in-memory history must be inspected separately from the file. Bash records
lines **as typed**, before variable expansion, so a command using `$NEW_APP_PWD`
leaves the variable name in the history, not the value.

Delete the old passwords from the password manager only once the new ones have
been verified in production.

---

## Rollback

If the API cannot reconnect and the cause is not obvious, revert the application
account to its previous value rather than debugging under outage:

```bash
read -rsp "ROOT password: " MYSQL_PWD; echo; export MYSQL_PWD
read -rsp "OLD taskflow password: " OLD_APP_PWD; echo

printf "ALTER USER 'taskflow'@'%%' IDENTIFIED BY '%s';\n" "$OLD_APP_PWD" \
  | docker exec -i -e MYSQL_PWD taskflow-db mysql -u root
```

Then restore the previous value of `DB_PASSWORD` in `/opt/taskflow/.env`,
`chmod 600`, and run `docker compose up -d` again.

The dump from step 1 is only needed if the database itself was damaged, which
credential rotation does not do. It is insurance, not part of the normal path.

---

## Known pitfalls

| Symptom | Cause | Fix |
|---|---|---|
| `Access denied for user 'taskflow'@'localhost'` during the dump | `MYSQL_PWD` holds the root password, or the wrong account's password | Reload `MYSQL_PWD` with the current application password |
| `you need (at least one of) the PROCESS privilege(s) ... tablespaces` | `mysqldump` lists InnoDB tablespaces by default | Add `--no-tablespaces`. Do not grant `PROCESS` to the application account |
| A zero-byte or truncated `.sql` file after a failed dump | The shell creates the redirection target before the command runs | Delete the file. A failed dump always leaves one behind |
| `taskflow-db` stays `unhealthy` after recreation | `MYSQL_ROOT_PASSWORD` holds the `root@localhost` value while the old healthcheck pings over TCP | Use the `root@'%'` value |
| `taskflow-api` never starts, no error of its own | `condition: service_healthy` is blocking on an unhealthy database | Fix the database first, the API is a symptom |
| The new password works nowhere after editing `.env` only | `MYSQL_USER` and `MYSQL_PASSWORD` are read at volume initialisation only | `ALTER USER` first. See the ordering constraint |

---

## Related

- Healthcheck credential exposure, fixed in the same pass: see the
  `taskflow-db` healthcheck comment in `docker-compose.yml`.
- `root@'%'` exists because the MySQL image creates it, not because the stack
  needs it. Removing it is tracked separately.
- Automated backups are tracked separately. Until they exist, the manual dump in
  step 1 is the only safety net.
