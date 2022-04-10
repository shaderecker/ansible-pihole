# ansible-pihole
Bootstrap a Raspberry Pi with Ansible and install Docker + Pi-hole

Optionally you can enable HA (high availability) with keepalived and sync settings between multiple instances.

The repository contains four Ansible Playbooks. Each one is described here shortly.

For more info about the Docker Pi-hole image please check the official repository: https://github.com/pi-hole/docker-pi-hole

## Base Setup
- An [Ansible](https://www.ansible.com/) controller machine with Ansible [installed](https://docs.ansible.com/ansible/latest/installation_guide/index.html) (version 2.10 or later)
- The [openssh_keypair](https://docs.ansible.com/ansible/latest/collections/community/crypto/openssh_keypair_module.html) Ansible module installed
- One or more Raspberry Pi's with [Raspberry Pi OS Lite](https://www.raspberrypi.com/software/operating-systems/) (bullseye)
- Headless setup (configuration before first boot):
  - Enable [SSH](https://www.raspberrypi.com/documentation/computers/remote-access.html#enabling-the-server) `"NOTE For headless setup..."`
  - Enable [wireless networking](https://www.raspberrypi.com/documentation/computers/configuration.html#configuring-networking-2) or connect with LAN  
    If you use LAN exclusively, consider disabling Wifi by adding `dtoverlay=disable-wifi` to `/boot/config.txt`
  - Configure a [user](https://www.raspberrypi.com/documentation/computers/configuration.html#configuring-a-user)

- Set static IPs for your Raspberry Pi's (static DHCP assignment/reservation in your Router/DHCP server is sufficient)
- Configure your targets (IPs and initial user + password of your Raspberry Pi's) and other settings in [`inventory.yaml`](inventory.yaml)  
You can add or remove hosts in the inventory, depending on how many Raspberry Pi's you use.

## `bootstrap-pihole.yaml`
This playbook is for the first time run (but it can be rerun any time).  
It will bootstrap a fresh Raspberry Pi OS installation, install Docker, and Pi-hole.  
You can run it with: `ansible-playbook -i inventory.yaml bootstrap-pihole.yaml`  

If the playbook fails during the first run while installing Docker, please reboot your Pi and re-run the playbook!

These roles are included:
- [`bootstrap`](roles/bootstrap/tasks/main.yaml): Some basic configuration  
  - Add the ssh key fetched from your GitHub user, configured in [`github_user_for_ssh_key`](inventory.yaml#L13) (Alternatively you can also set your ssh key directly [here](roles/bootstrap/tasks/main.yaml#L3))
  - Lock the password to prevent local terminal login
  - Set some useful bash aliases
  - Set timezone, configured in [`timezone`](inventory.yaml#L14)
  - Set hostname to the respective Ansible inventory_hostname
  - Set a static DNS server, configured in [`static_dns`](inventory.yaml#L15)
- [`updates`](roles/updates/tasks/main.yaml): Update apt packages
- [`sshd`](roles/sshd/tasks/main.yaml): Harden the sshd config  
  - Disable root login
  - Disable password authentication
- [`docker`](roles/docker/tasks/main.yaml): Install and configure Docker
- [`pihole`](roles/pihole/tasks/main.yaml): Start/Update Pi-hole container
  - Pi-hole container settings are configured in [`inventory.yaml`](inventory.yaml#L16-L23)  
    The options prefixed with `pihole_` are described in the official [docker-pi-hole readme](https://github.com/pi-hole/docker-pi-hole#environment-variables)  
    (except for `pihole_image`, `pihole_ha_mode`, `pihole_vip_ipv4`, `pihole_vip_ipv6`: those are custom variables of this playbook)  
    The options prefixed with `pihole_ftl_` are described in the official [Pi-hole FTL Configuration](https://docs.pi-hole.net/ftldns/configfile/)
  - The [`pihole_ha_mode`](inventory.yaml#L24) option is used to switch between HA or Single mode to determine the IPv4/IPv6 addresses for the Pi-hole services (bind IPs for Web/DNS, pi.hole DNS record) and is enabled by default.  
    ⚠️ Disable this if you don't intend to deploy a HA setup with keepalived.

## `update-pihole.yaml`
This playbook is for subsequent runs after the `bootstrap-pihole.yaml` playbook was run at least once.  
You can run it with: `ansible-playbook -i inventory.yaml update-pihole.yaml`  
It contains only a subset of roles for faster runtime: [`updates`](roles/updates/tasks/main.yaml) and [`pihole`](roles/pihole/tasks/main.yaml)  
This will keep the system up to date and can be used to roll out changes to the Pi-hole docker container, for example a new image version.

## `keepalived.yaml`
This playbook enables a high availability failover cluster with `keepalived` between multiple Pi-hole instances.  
You can run it with: `ansible-playbook -i inventory.yaml keepalived.yaml`  

Motivation:  
- Redundancy: Avoid a single point of failure (due to raspberry pi reboot, docker container failure/update/restart)
- Architecture of DNS requires a HA solution on the DNS server side (most clients will not properly handle unavailable DNS servers; if a client has multiple DNS servers configured it will try them one after another only moving on if one times out)
- Poor DNS query performance during system updates & docker image pulls (experienced on my Pi 3 Model B)

As healthcheck, the status of the Pi-hole docker container is evaluated.  
Communication happens over VRRP (Virtual Router Redundancy Protocol) which uses Multicast.  
The priority of each Pi-hole can be configured in [`inventory.yaml`](inventory.yaml), for example:
```yaml
    pihole-1:
      ansible_host: 192.168.178.45
      priority: 101
```
The desired VIPs (Virtual IPs) for IPv4 and IPv6 can be configured in [`inventory.yaml`](inventory.yaml#L25-L26):
```yaml
    pihole_vip_ipv4: "192.168.178.10/24"
    pihole_vip_ipv6: "fd00::10/64"
```

When maintaining and updating your Pi-hole instances with the `bootstrap-pihole.yaml` and `update-pihole.yaml` playbooks, the first step stops keepalived and therefore shifts the VIP to another instance so that the performance of DNS queries is not impeded.

## `sync.yaml`
This playbook enables the synchronisation of settings between multiple Pi-hole instances.  
You can run it with: `ansible-playbook -i inventory.yaml sync.yaml`  
One Pi-hole functions as the primary instance and the others as secondaries which pull from the primary.  
Syncing is scheduled as a cronjob and set to run two times per day (frequency can be changed [here](roles/sync/tasks/main.yaml#L28)).  
What gets synced:
- `gravity.db` (Adlists, Domains, Clients, Groups, Group Assignments of all aforementioned items)
- `custom.list` (Local DNS Records)
- `05-pihole-custom-cname.conf` (Local CNAME Records)

#### Default: Pull from VIP
If you enabled HA (high availability) with the `keepalived.yaml` playbook, the primary instance will be the one currently occupying the Virtual IP address (evaluated at each cronjob run).

```yaml
sync_target: "{{ pihole_vip_ipv4.split('/')[0] }}"
```

#### Alternative: Pull from primary instance
You can set the [`sync_target`](inventory.yaml#L27) variable to the IP address of your primary Pi-hole instance (in my example `pihole-1`, otherwise adapt).
```yaml
sync_target: "{{ hostvars['pihole-1'].ansible_host }}"
```

For syncing, `rsync` is used which will only transfer files if they contain changes.  
Changes to `gravity.db` will trigger a docker container restart to pick up the changes.  
Changes to DNS & CNAME records get picked up on the fly.
