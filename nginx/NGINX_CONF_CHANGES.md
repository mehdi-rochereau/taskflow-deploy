# Divergences from the packaged `nginx.conf`

`/etc/nginx/nginx.conf` is a dpkg conffile. It is not versioned in this
repository, and it is not copied from it either: a package update prompts before
overwriting it, and freezing a copy here would produce a file diverging from the
distribution's without anything saying which parts came from where.

What follows is the list of every deliberate divergence from the file shipped by
`nginx` `1.24.0-2ubuntu7.17` on Ubuntu 24.04, so the change can be reapplied on
a fresh install and audited on an existing one.

## `ssl_protocols`

| | |
|---|---|
| Section | `http`, under `SSL Settings` |
| Shipped | `ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;` |
| Retained | `ssl_protocols TLSv1.2 TLSv1.3;` |
| Since | 26 August 2026, issue #31 |

TLS 1.0 and 1.1 have been deprecated since 2021 and offer nothing a current
client needs.

Both vhosts already escaped the shipped value, because `options-ssl-nginx.conf`
redeclares the safe pair at `server` level. The exposure was to any future 443
`server` block that forgot that include: it would have inherited TLS 1.0 and
1.1 with no warning at all. The catch-all vhost of #37 is exactly such a block.

The fix does not live in `conf.d/10-hardening.conf`, where the rest of the
server-wide hardening does, and the reason is not obvious. `ssl_protocols` is a
bit mask: a second declaration in the same context merges into the first instead
of replacing it. `conf.d/*.conf` is included into the same `http` block that
declares it, so a hardening written there emits `duplicate value` warnings,
passes `nginx -t`, and leaves the unwanted protocols enabled. Tested on the VPS
on 26 August 2026.

Reapply on a fresh install:

```bash
sudo sed -i 's/^\(\s*\)ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;.*/\1ssl_protocols TLSv1.2 TLSv1.3;/' /etc/nginx/nginx.conf
sudo nginx -t
```

Audit an existing one:

```bash
sudo nginx -T | grep ssl_protocols
```

The expected output carries `TLSv1.2` and `TLSv1.3` only, on every line. Run it
again after any `nginx` package upgrade: dpkg prompts before overwriting a
modified conffile, and accepting the maintainer's version at that prompt puts
the deprecated protocols back.