# Database Credential Rotation

Rotating the MySQL passwords of the TaskFlow production stack.

Applies to two accounts: `taskflow@'%'`, the application account, and
`root@localhost`, the only remaining administrative account.

A third account exists, `healthcheck@'%'`, used by the `taskflow-db` Docker
healthcheck. It holds `USAGE` only, reaches no database, table or row, and has
no password, so there is nothing to rotate. It is listed here so that the
inventory is complete and so that nobody mistakes it for an omission. See
issue #27.

`root@'%'` was dropped on 15 August 2026, see issue #20. It accepted connections
from any host on the Docker network and had no remaining use once the healthcheck
stopped authenticating as root. Any older instruction mentioning it no longer
applies.

Where each value lives:

| Account | Consumed by | Stored in |
|---|---|---|
| `taskflow@'%'` | the API, at every start | `DB_PASSWORD` in `/opt/taskflow/.env`, and `/home/mehdi/secrets/mysql_password` |
| `root@localhost` | nothing, by design | `/home/mehdi/secrets/mysql_root_password`, and the password manager |
| `healthcheck@'%'` | the `taskflow-db` healthcheck, every 10 seconds | nowhere, the account has no password |

The two files under `/home/mehdi/secrets/` are mounted into `taskflow-db` as
Docker Compose secrets. The MySQL image reads them **only when the data volume is
first initialised**, so on the existing volume they are inert. They exist so that
a rebuild from scratch produces the accounts this procedure expects. Rotating a
password means running `ALTER USER` **and** updating the file, otherwise the two
diverge silently and only a rebuild reveals it.

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
2. then `/opt/taskflow/.env` and the files under `/home/mehdi/secrets/`
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

### 3. Rotate the root account

Only `root@localhost` remains. In MySQL an account is a name/host pair, and this
one is reachable through the Unix socket alone: connections over TCP, including
from other containers, have no root account to authenticate against since
`root@'%'` was dropped.

```bash
read -rsp "NEW root@localhost password: " NEW_ROOT_PWD; echo

printf "ALTER USER 'root'@'localhost' IDENTIFIED BY '%s';\n" "$NEW_ROOT_PWD" \
  | docker exec -i -e MYSQL_PWD taskflow-db mysql -u root
```

`MYSQL_PWD` still holds the **old** root password here, which is what
authenticates this statement.

Then update the secret file, or the next rebuild from scratch will create a root
account with the previous password:

```bash
printf '%s' "$NEW_ROOT_PWD" > /home/mehdi/secrets/mysql_root_password
chmod 600 /home/mehdi/secrets/mysql_root_password
```

`printf '%s'` without a newline is not cosmetic: the MySQL image reads the file
verbatim, and a trailing newline becomes part of the password.

### 4. Record the start of the outage window

```bash
date -u +'%Y-%m-%dT%H:%M:%SZ'
```

### 5. Update the environment file

```bash
nano /opt/taskflow/.env
chmod 600 /opt/taskflow/.env
```

One line changes: `DB_PASSWORD`, consumed by the API at every start.

`MYSQL_ROOT_PASSWORD` is no longer in this file. Since issue #20 the database
receives its passwords through Docker Compose secrets, and `docker inspect` shows
only paths. The root value lives in `/home/mehdi/secrets/mysql_root_password` and
in the password manager, nowhere else.

Also update the application secret file, for the same reason as the root one in
step 3:

```bash
printf '%s' "$NEW_APP_PWD" > /home/mehdi/secrets/mysql_password
chmod 600 /home/mehdi/secrets/mysql_password
```

`chmod 600` is mandatory after any edit, on the `.env` and on both secret files.
Editors do not preserve permissions.

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
unset MYSQL_PWD NEW_APP_PWD OLD_APP_PWD NEW_ROOT_PWD STAMP
env | grep -cE 'MYSQL_PWD|_APP_PWD|_ROOT_PWD'

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
| `ERROR 1045` connecting as root over TCP | `root@'%'` was dropped on 15 August 2026. Root authenticates through the Unix socket only | Use `docker exec` without `-h`, which takes the socket |
| A rebuild from scratch produces accounts with old passwords | `ALTER USER` was run without updating the files under `/home/mehdi/secrets/` | Rotate both: the statement and the file |
| The password in a secret file is rejected | A trailing newline was written into it, and the MySQL image reads the file verbatim | Rewrite with `printf '%s'`, never `echo` |
| `taskflow-api` never starts, no error of its own | `condition: service_healthy` is blocking on an unhealthy database | Fix the database first, the API is a symptom |
| The new password works nowhere after editing `.env` only | `MYSQL_USER` and `MYSQL_PASSWORD` are read at volume initialisation only | `ALTER USER` first. See the ordering constraint |

---

## Related

- Healthcheck credential exposure, fixed on 15 August 2026, and the dedicated
  healthcheck account added on 17 August 2026, issue #27: see the `taskflow-db`
  healthcheck comment in `docker-compose.yml`.
- `root@'%'` was dropped and the database passwords moved to Compose secrets on
  15 August 2026, issue #20.
- Automated daily backups exist since 15 August 2026, issue #17. The manual dump
  in step 1 remains the right move before any credential change.
- Restoring a database: `DATABASE_RESTORE.md`.
