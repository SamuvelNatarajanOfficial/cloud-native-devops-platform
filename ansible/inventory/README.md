# Inventory

## Layout

```
inventory/
└── dev/
    ├── hosts.yml         # hosts + group membership for the "dev" environment
    └── group_vars/
        └── all.yml       # variables applied to every host in this environment
```

Additional environments (e.g. `staging/`, `prod/`) would follow the same
shape as a sibling directory - nothing else in this repo needs to change
to add one, since `ansible.cfg`'s `inventory` setting is just a default
that `-i` overrides.

## Pointing this at your own server

`inventory/dev/hosts.yml` ships with a placeholder host so the repository
never contains a real IP address or hostname:

```yaml
dev_servers:
  hosts:
    dev-server-1:
      ansible_host: "REPLACE_WITH_YOUR_SERVER_IP_OR_HOSTNAME"
      ansible_user: ubuntu
```

To use it against a real machine (an EC2 instance, a home lab VM, anything
running Ubuntu that you control):

1. **Don't edit `hosts.yml` in place if you plan to keep working in this
   repo** — copy it instead so your real value never gets committed:
   ```bash
   cp inventory/dev/hosts.yml inventory/dev/hosts.local.yml
   # edit hosts.local.yml with your real ansible_host
   ```
   `inventory/**/hosts.local.yml` is gitignored (see the repo root
   `.gitignore`) specifically so this pattern is safe.
2. Make sure you can already reach the server with plain SSH first:
   ```bash
   ssh ubuntu@<your-server-ip>
   ```
   This is also what populates your `known_hosts` entry - `ansible.cfg`
   keeps `host_key_checking` on, so Ansible will refuse to connect to a
   host it can't already verify.
3. Confirm Ansible can reach it:
   ```bash
   cd ansible
   ansible dev_servers -i inventory/dev/hosts.local.yml -m ping
   ```

## Variables

Host/group variables follow normal Ansible precedence. `group_vars/all.yml`
holds the lab-wide defaults (timezone, app user, Node Exporter port, and
the SSH-hardening opt-out); role-level defaults in
`roles/*/defaults/main.yml` document every variable a role actually reads.
