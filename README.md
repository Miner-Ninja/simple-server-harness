# Simple Server Harness

Ansible setup for a fresh Ubuntu server: user account, swap, Docker, firewall,
Fail2Ban, SSH hardening. It configures a machine that already exists and that
you can reach over SSH. It does not create one.

## What it does

| Playbook | Result |
|----------|--------|
| `validate-config.yml` | Stops the run if settings or secrets are missing |
| `time-zone-config.yml` | System timezone |
| `swap-config.yml` | Swap file, `/etc/fstab`, `vm.swappiness` |
| `user-config.yml` | User with sudo, password, SSH key |
| `docker-install.yml` | Docker CE, Compose plugin, log rotation, overlay2 |
| `docker-rootless-install.yml` | The same, but the daemon runs as your user |
| `firewall-config.yml` | UFW: deny incoming, allow SSH and app ports |
| `fail2ban-config.yml` | Jails for SSH and port scans, email alerts |
| `system-update.yml` | Full upgrade, optional reboot |
| `ssh-config.yml` | Key-only SSH on a non-standard port, strong crypto; root login and passwords refused |

## Files

```
simple-server-harness/
├── ansible.cfg                  # inventory path, SSH options
├── inventory.yml                # points at the vault; nothing to fill in
├── group_vars/all/vars.yml      # all settings
├── group_vars/all/vault_template.tpl  # the same values, as a template
├── group_vars/all/vault.yml     # address, account, ports, keys, passwords - encrypted
├── LICENSE                      # MIT
└── ansible/
    ├── ansible-tasks.yml        # entry point, runs everything in order
    └── tasks/
        ├── docker-common.yml    # task list shared by both docker playbooks
        └── ...                  # one file per playbook
```

## Requirements

- Ansible (tested with ansible-core 2.21)
- Two collections: `ansible-galaxy collection install ansible.posix community.general`
  (`ansible.posix` for the sysctl and authorized_key modules, `community.general`
  for the firewall). Both come with the full `ansible` package; the plain
  `ansible-core` needs them installed.
- Python 3 and `ssh` on the machine you run it from
- A server reachable over SSH with a key

## Quick start

1. `inventory.yml` holds nothing of yours at all: the address, the port and
   the private key it connects with come from the vault, the login name from
   the settings. There is nothing to edit there.

2. `group_vars/all/vars.yml`: the settings. The run stops if anything is empty.

3. Secrets:

   ```bash
   ansible-vault create group_vars/all/vault.yml
   ```

   It asks for a password and then opens an editor. Copy the values from
   `vault_template.tpl` and fill them in — the vault holds the server
   address, the port it connects on and the port SSH moves to, the key to
   connect with, the account name, the login password and the notification
   addresses.

4. Run it, from the repository root:

   ```bash
   ansible-playbook ansible/ansible-tasks.yml --ask-vault-pass
   ```

5. The first run moves SSH to the new port. Put that same port into
   `vault_ssh_default_port` in the vault before the next run. Port 22 stays open
   until then, so the first run cannot lock itself out, and closes by itself
   on the run after you have moved over.

If you log in as `root` because the user does not exist yet, run the
first pass with `-e ansible_user=root`.

## Settings

The settings you fill in sit in `group_vars/all/vars.yml`:

| Setting | Meaning |
|---------|---------|
| `use_sudo_ws` | `true` on Ubuntu 25.10 and newer, `false` on 24.04 and older |
| `ssh_max_auth_tries`, `ssh_login_grace_time`, `ssh_client_alive_*` | Session limits, rarely worth changing |
| `timezone` | e.g. `Europe/Berlin` |
| `swap_size`, `swappiness` | Swap file size, `/proc/sys/vm/swappiness` |
| `install_docker` | `false` skips Docker entirely, for a server that runs nothing containerised |
| `docker_rootless` | `false`: system daemon, docker commands need sudo. `true`: daemon runs as `server_user`, no sudo. Ignored when `install_docker` is `false` |
| `extra_firewall_tcp_ports`, `extra_firewall_udp_ports` | Ports to open for applications, comma-separated on one line: `8080, 5432`. An empty line means no ports |
| `fail2ban_bantime`, `fail2ban_findtime`, `fail2ban_maxretry` | Ban policy |
| `fail2ban_ignore_ip` | Networks that are never banned |
| `auto_reboot` | Reboot when updates require it |
| `update_timeout` | Timeout for the upgrade, seconds |

The values that would tell an attacker where to aim are in the encrypted
vault instead:

- `vault_server_host` — the address Ansible connects to
- `vault_ssh_default_port` — the port it connects on now, 22 on a fresh server
- `vault_ssh_remaped_port` — the port sshd moves to; the same value goes into
  `vault_ssh_default_port` once the first run has moved it
- `vault_private_key_file` — the private key Ansible connects with; the file
  without `.pub`
- `vault_public_key_file` — the public half, the `.pub` file; it is what gets
  installed on the server
- `vault_server_user` — the account that will exist on the server: sudo, the
  SSH key, sshd `AllowUsers`
- `vault_server_password` — its login password. Sudo asks for the same one, so
  there is no separate `become` password
- `vault_fail2ban_dest_email`, `vault_fail2ban_sender` — where Fail2Ban sends
  its notices

The template for the vault lies next to it, under the name
`vault_template.tpl`. The `.tpl` on the end is what keeps it harmless: only
files with a YAML extension are read from that directory, and a template read
after the vault would override the real secrets with its placeholders.

## Adding an application

1. Put its playbook in `ansible/tasks/apps/`.
2. Add its ports to `extra_firewall_tcp_ports` / `extra_firewall_udp_ports` in
   `group_vars/all/vars.yml` — comma-separated on one line, for example
   `8080, 5432`. The application must not touch UFW itself:
   `firewall-config.yml` rebuilds the rule set on every run.
3. Import it in `ansible/ansible-tasks.yml`, between the base tasks.

Three things to keep in mind:

- Container applications go after `docker-install.yml`.
- SSH hardening stays last. It moves the port, so nothing may come after it
  that has to dial the old one.
- `system-update.yml` can reboot the server. It runs while SSH is still on
  the port it was reached on, so the connection stays predictable.

## Notes

- Running it again changes nothing unless something actually differs.
- Ubuntu 25.10 and newer ship `sudo-rs` as the plain `sudo`, and Ansible cannot
  work with it: Ansible asks sudo to print a marker and then waits for that
  text, while sudo-rs wraps the marker inside its own `[sudo: ...] Password:`
  line. The wait ends in `Timeout waiting for privilege escalation prompt` and
  no task ever runs. The classic sudo is still installed there, under the name
  `sudo.ws`, which is what `use_sudo_ws: true` picks. On 24.04 and older the
  plain `sudo` already is the classic one, so set it to `false`. The run stops
  with a plain message if the file the setting names is missing or turns out
  not to be the classic sudo.
- Nobody is ever put into the `docker` group: membership there is root without
  a password. With `docker_rootless: false` that leaves sudo as the only way to
  run docker; with `true` the daemon belongs to `server_user` and sudo is not
  involved at all. Decide when the server is built — switching an existing
  machine from one to the other is not handled.
- `firewall-config.yml` resets UFW and rebuilds the rules every run. Rules
  added on the server by hand are lost.
- `user-config.yml` sets the account password once, when the account is
  created. To change it later, use `passwd`.
- Host key checking is off in `ansible.cfg`. A server that was just built has
  no key in `known_hosts` yet, so the first connection would stop and ask. Turn
  it on and add the key by hand if you want the check.
- On Ubuntu 24.04 and newer the SSH port belongs to the systemd socket, not to
  the daemon, so `Port` in `sshd_config` alone does nothing. `ssh-config.yml`
  writes it to both. It restarts the socket instead of stopping it, because
  stopping takes the service down and cuts the connection doing the work.

## Tested

Against throwaway Ubuntu 24.04 and 26.04 containers on ansible-core 2.21:

- Full runs finished green on both. A second run over the new port changed
  nothing except the firewall and the update log, which rewrite themselves.
- SSH ended up on 22222 with root login and passwords off and `AllowUsers`
  limited to the one account: that account could log in on the new port, root
  could not. Port 22 stayed open through the first run and was gone from the
  firewall after the second, with no setting to flip by hand.
- With the port left at 22, nothing moves. The daemon keeps listening on both
  address families, port 22 keeps its single rule, and the closing report says
  there is nothing to change.
- UFW came up with exactly the configured ports: adding one to
  `extra_firewall_tcp_ports` opened it, taking it out closed it, and an empty
  line opened nothing.
- Fail2Ban came up with the `sshd` and `portscan` jails, and a ban was followed
  end to end: failed logins, the ban, the rule appearing in the firewall, and
  the banned address refused afterwards.
- A path in `vault_public_key_file` that points at nothing stops the run
  before it touches the server.
- Swap: create, format, activate and `/etc/fstab` all worked, and a second run
  changed nothing.
- Docker, both modes. `rootful`: the daemon started on overlay2 with log
  rotation, both commands answered, plain `docker ps` as the user account was
  refused and `sudo docker ps` worked. `rootless`: the system-wide daemon was
  left disabled, the daemon came up as the user account and reported itself as
  rootless, and containers ran as that account with no sudo anywhere.

## License

MIT, see [LICENSE](LICENSE).
