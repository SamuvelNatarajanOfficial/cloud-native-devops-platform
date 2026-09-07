# Ansible — configuration management & server automation (Phase 3)

## Purpose

Terraform (Phase 2, [../terraform/](../terraform/)) provisions AWS
infrastructure. This directory configures the **operating system** on a
Linux server once it exists: packages, timezone, an application user,
Docker, Prometheus Node Exporter, and basic security hardening.

**Scope note:** these roles target a general-purpose Ubuntu server
reachable over SSH (e.g. a standalone EC2 instance, a home lab VM, a small
bastion/monitoring host) — **not** the EKS managed node group Terraform
creates. EKS worker nodes are provisioned and patched by AWS directly;
nothing here runs against them. See
[docs/ansible-architecture.md](../docs/ansible-architecture.md) for the
full architecture diagram and how this fits with Terraform/Kubernetes.

## Architecture

```
ansible/
├── ansible.cfg              # inventory/roles paths, safe defaults (see below)
├── requirements.yml          # third-party collection dependency (community.general)
├── .ansible-lint             # lint profile/config
├── inventory/
│   └── dev/
│       ├── hosts.yml         # placeholder host - see "Inventory setup"
│       └── group_vars/all.yml
├── playbooks/
│   ├── site.yml              # everything: common + docker + node_exporter + hardening
│   ├── configure_servers.yml # common + docker + node_exporter (no hardening)
│   └── hardening.yml         # hardening only
└── roles/
    ├── common/                # base OS config: packages, timezone, app user, MOTD
    ├── docker/                # Docker Engine install + config
    ├── node_exporter/         # pinned Prometheus Node Exporter, as a systemd service
    └── hardening/             # auto security updates, unneeded services off, opt-in SSH hardening
```

Each role owns one concern, with a typed interface
(`defaults/main.yml` in → task effects out) - the same reasoning
[Phase 2's Terraform modules](../docs/aws-architecture.md#why-terraform-modules)
use, applied to configuration management instead of infrastructure.

## Prerequisites

- Ansible (`ansible-core` >= 2.15) and `ansible-lint` on your control
  machine (where you run `ansible-playbook` from) - **not** on the target
  server; Ansible only needs Python + SSH access on the target.
  ```bash
  pip install ansible-core ansible-lint
  ```
- The `community.general` collection (used for one module - see
  [Idempotency](#idempotency) below):
  ```bash
  ansible-galaxy collection install -r requirements.yml
  ```
- A target Ubuntu server (22.04/24.04) you control, reachable over SSH
  with a key (not a password), and passwordless (or interactive, via
  `--ask-become-pass`) `sudo` for the SSH user.
- **Ansible's control node itself must run on Linux/macOS/WSL** —
  `ansible-core` depends on POSIX-only Python modules (`grp`, `pwd`,
  `fcntl`) and does not run as a control node on native Windows. If
  you're on Windows, run it from WSL, as this repo's own validation did.

## Inventory setup

`inventory/dev/hosts.yml` ships with a placeholder, not a real
IP/hostname — this is a public repository. See
[inventory/README.md](inventory/README.md) for the full explanation and
the recommended `hosts.local.yml` (gitignored) pattern for pointing this
at a real server without ever committing its address.

## Variables

Every variable a role reads is declared with a default in that role's
`defaults/main.yml`, and the role-prefixed naming (`common_*`, `docker_*`,
`node_exporter_*`, `hardening_*`) makes it unambiguous which role a given
override belongs to. The most relevant ones:

| Variable | Role | Default | Purpose |
|---|---|---|---|
| `common_timezone` | common | `UTC` | System timezone (Olson name) |
| `common_packages` | common | curl, vim, git, unzip, ca-certificates, gnupg, htop | Base packages installed on every host |
| `common_app_user` / `common_app_group` | common | `taskflow` | Application system account |
| `docker_package_state` | docker | `present` | apt state for Docker packages |
| `docker_add_app_user_to_group` | docker | `true` | Add `common_app_user` to the `docker` group |
| `node_exporter_version` | node_exporter | `1.8.2` | Pinned release - never `latest` |
| `node_exporter_listen_port` | node_exporter | `9100` | `--web.listen-address` port |
| `hardening_manage_ssh` | hardening | `false` | Master switch for SSH hardening - **off by default, see below** |

`inventory/dev/group_vars/all.yml` sets the lab-wide defaults for a few of
these; everything else falls back to the role default shown above.

## Running the playbooks

```bash
cd ansible

# Full configuration (common + docker + node_exporter + hardening):
ansible-playbook -i inventory/dev/hosts.local.yml playbooks/site.yml

# Base software only, no hardening:
ansible-playbook -i inventory/dev/hosts.local.yml playbooks/configure_servers.yml

# Hardening only:
ansible-playbook -i inventory/dev/hosts.local.yml playbooks/hardening.yml

# Override a variable for one run without editing group_vars:
ansible-playbook -i inventory/dev/hosts.local.yml playbooks/site.yml \
  -e node_exporter_version=1.9.0
```

(`hosts.local.yml` is the gitignored copy of `hosts.yml` with your real
server's address - see [Inventory setup](#inventory-setup).)

## Check mode / dry run

**Always review a diff before applying anything for real:**

```bash
# Parse-only, no connection to any host:
ansible-playbook playbooks/site.yml --syntax-check

# Static analysis, no connection to any host:
ansible-lint

# Confirm the inventory parses the way you expect:
ansible-inventory -i inventory/dev/hosts.local.yml --graph
ansible-inventory -i inventory/dev/hosts.local.yml --list

# Dry run against the real target - connects over SSH and reports what
# WOULD change, without changing it:
ansible-playbook -i inventory/dev/hosts.local.yml playbooks/site.yml --check --diff
```

`--check --diff` is the most important command in this list: it shows you
the exact before/after of every file Ansible would touch (rendered
templates included) before you ever run it for real. Run every playbook
this way at least once against a new host before dropping `--check`.

## Ansible-lint

```bash
cd ansible
ansible-lint
```

Configured via [`.ansible-lint`](.ansible-lint) to the **`safety`**
profile - stricter than the default (enforces fully-qualified module
names, safe file permissions, no plain-text secrets, and more) without
the `production` profile's Galaxy-collection-specific requirements
(changelog fragments, `meta/runtime.yml`, etc.) that don't apply to a
single-repo project like this one. There is no `skip_list`/`warn_list` in
this config — every lint finding encountered while building this phase
was fixed, not silenced.

## Idempotency

Every task in every role uses a proper Ansible module
(`apt`/`deb822_repository`, `user`, `group`, `file`, `template`, `copy`,
`get_url`, `unarchive`, `systemd`, `community.general.timezone`) instead
of `shell`/`command` — **no `shell:` or `command:` task exists anywhere in
this repo's roles.** Every one of those modules is idempotent by design:
each computes whether the system already matches the desired state and
only reports `changed` (and only actually changes anything) when it
doesn't. That's what makes `ansible-playbook --check` meaningful in the
first place, and it's why running any of these playbooks twice in a row
against the same host reports far fewer (typically zero, outside a
version bump) changes on the second run than the first.

`community.general.timezone` is the one exception to "ansible.builtin
only" — there's no core module for timezone configuration, and
hand-rolling it with `file`/`copy` against `/etc/timezone` and
`/etc/localtime` would have been a worse, less-tested reimplementation of
a module that already exists and already handles the OS-specific details
correctly.

## Handlers

Handlers only fire when a task actually reports `changed` — they're not
run on every play:

- `common`: **Restart cron** — notified by the timezone task, since cron
  caches the timezone at startup.
- `docker`: **Restart docker** — notified by the `daemon.json` template
  task (log-rotation config), not by the install task (installing/
  upgrading the package already (re)starts the service on Ubuntu).
- `node_exporter`: **Reload systemd daemon** then **Restart
  node_exporter** — both notified by the systemd unit template task.
  Handlers run in the order they're *defined* in `handlers/main.yml`
  (not the order notified), so the file lists `Reload systemd daemon`
  first to guarantee `daemon-reload` always happens before the restart
  that depends on it.
- `hardening`: **Reload SSH service** — notified only by the (opt-in)
  SSH hardening drop-in template task. Reload, not restart, so an
  in-progress SSH session isn't dropped.

## Security considerations

- **No secrets, keys, or real addresses are committed.** The inventory
  ships a placeholder host (`REPLACE_WITH_YOUR_SERVER_IP_OR_HOSTNAME`);
  see [inventory/README.md](inventory/README.md) for the gitignored
  `hosts.local.yml` pattern.
- **`host_key_checking` stays on** in `ansible.cfg` - see the comment
  there for the one-time-`ssh`-then-Ansible workflow instead of disabling
  it.
- **No `.retry` files** — `retry_files_enabled = False` in `ansible.cfg`,
  so there's nothing generated that could accidentally leak host details
  into a commit.
- **No IAM user, AWS credential, or long-lived secret is used or created
  by anything in this directory** — Ansible here only ever needs SSH key
  access to a Linux host, nothing AWS-specific.
- **SSH hardening is opt-in and off by default.** `hardening_manage_ssh:
  false` means `playbooks/hardening.yml` and `playbooks/site.yml` do not
  touch SSH access at all out of the box. Before ever setting it to
  `true`:
  1. Confirm you can already SSH into the target using a key (not a
     password) — the hardening drop-in can disable password
     authentication and root login.
  2. Run with `--check --diff` first.
  3. Keep an existing SSH session to the host open while you apply it for
     the first time, so you have a way back in if something's wrong.
  4. Note that the deployed config is validated with `sshd -t` (via the
     `template` module's `validate` parameter) **before** it's ever
     installed — a config that fails to parse is rejected outright and
     never reaches `/etc/ssh/sshd_config.d/`, so a syntax mistake can't
     brick SSH access. It cannot, however, protect you from a *valid*
     config that disables the only auth method you actually have set up
     (step 1 above is what protects you from that).
- This is **portfolio-level hardening**, not a CIS/DISA benchmark or a
  claim of complete security hardening — see
  [docs/ansible-architecture.md](../docs/ansible-architecture.md#deliberately-out-of-scope-for-phase-3).

### Ansible Vault (if you ever need it)

No task in this repo currently needs a secret, so Vault isn't used here —
adding it just to demonstrate the feature would mean encrypting something
that doesn't need to be encrypted. If a later phase needs one (e.g. an
API token for a real observability backend), the pattern to follow is:

```bash
ansible-vault create group_vars/all/vault.yml   # prompts for a vault password
ansible-playbook site.yml --ask-vault-pass       # or --vault-password-file
```

**Never commit the vault password itself** (as a file or in `ansible.cfg`)
— only the encrypted `vault.yml` content is safe to commit; the password
that decrypts it is not.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `ansible-playbook` fails immediately with an import error (`No module named 'grp'` or similar) | You're running the control node on native Windows. Use WSL, Linux, or macOS instead - see Prerequisites. |
| `UNREACHABLE! ... Permission denied (publickey)` | `ansible_user`/SSH key don't match the target, or you haven't connected once with plain `ssh` yet to accept its host key (`host_key_checking` is on - see `ansible.cfg`). |
| A task fails with `... must be installed to use check mode` | Some modules (e.g. `deb822_repository`) need a Python library already present on the target to fully simulate `--check`. This is a real, documented `--check` limitation for that module, not a bug in the role - the equivalent real (non-check) run installs that prerequisite in an earlier task in the same role. |
| `hardening` role's SSH task never runs | Expected - `hardening_manage_ssh` defaults to `false`. See [Security considerations](#security-considerations). |
| Node Exporter fails to start after a version bump | Confirm `node_exporter_arch` matches the target's actual architecture (`amd64`/`arm64`) and that `node_exporter_version` is a real published release tag. |

## How this fits with Terraform

See [docs/ansible-architecture.md](../docs/ansible-architecture.md) for
the full diagram, but in short:

- **Terraform** creates AWS networking, IAM, and the EKS cluster/node
  group (Phase 2).
- **Ansible** (this phase) configures the operating system on a
  standalone Linux server: packages, users, Docker, Node Exporter, basic
  hardening.
- **Kubernetes/EKS** will eventually run application workloads (not yet
  wired up - see the root [README](../README.md)'s roadmap).
- **ArgoCD** will eventually manage what's deployed onto that cluster via
  GitOps (a future phase).

Neither tool tries to do the other's job — see
[docs/ansible-architecture.md](../docs/ansible-architecture.md#why-terraform-and-ansible-not-just-one-tool)
for why.
