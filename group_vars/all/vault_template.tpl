---
# Copy these into the encrypted vault. Both commands ask for the password:
#   ansible-vault create group_vars/all/vault.yml
#   ansible-vault edit   group_vars/all/vault.yml

# Where the server is, and the two halves of the key pair Ansible works with.
# Not written where it could be published: knowing the address and the ports is
# most of what an attack needs.
#
# The names say which half is which, so they cannot be swapped by accident:
# the private key is the one Ansible connects with, the public one is what gets
# installed on the server.
vault_server_host: "203.0.113.10"

# The static hostname the machine gets. The harness also stops cloud-init from
# putting the provider's default back after a reboot.
vault_server_hostname: "server1"

# The account Ansible logs in as. On a fresh server that is root, because the
# real account does not exist yet. After the first run set this to the account
# name from vault_server_user, so the same command keeps working.
vault_ssh_login_user: "root"
vault_private_key_file: "/home/you/.ssh/id_ed25519"
vault_public_key_file: "/home/you/.ssh/id_ed25519.pub"

# The port SSH is on now, and the port the harness moves it to. On a fresh
# server the first one is the standard 22; after the first run the second
# becomes the one Ansible connects on too.
vault_ssh_default_port: 22
vault_ssh_remaped_port: 22222

# The account that will exist on the server.
vault_server_user: "user"

# Login password of that account. SSH is key-only, so this is for console
# access and for sudo.
vault_server_password: ""

# Where Fail2Ban sends its notices.
vault_fail2ban_dest_email: ""
vault_fail2ban_sender: ""
