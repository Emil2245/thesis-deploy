locals {
  server_private_ip = "10.0.1.10"
  agent_private_ips = [for i in range(var.agent_count) : "10.0.1.${20 + i}"]
  labels            = { cluster = var.cluster_name, managed-by = "opentofu" }
}

resource "hcloud_ssh_key" "admin" {
  name       = "${var.cluster_name}-admin"
  public_key = file(pathexpand(var.ssh_public_key_path))
  labels     = local.labels
}

resource "hcloud_network" "main" {
  name     = var.cluster_name
  ip_range = "10.0.0.0/16"
  labels   = local.labels
}

resource "hcloud_network_subnet" "main" {
  network_id   = hcloud_network.main.id
  type         = "cloud"
  network_zone = data.hcloud_location.main.network_zone
  ip_range     = "10.0.1.0/24"
}

data "hcloud_location" "main" {
  name = var.location
}

resource "hcloud_firewall" "main" {
  name   = var.cluster_name
  labels = local.labels

  rule {
    description = "HTTP"
    direction   = "in"
    protocol    = "tcp"
    port        = "80"
    source_ips  = ["0.0.0.0/0", "::/0"]
  }
  rule {
    description = "HTTPS"
    direction   = "in"
    protocol    = "tcp"
    port        = "443"
    source_ips  = ["0.0.0.0/0", "::/0"]
  }
  rule {
    description = "SSH (admin)"
    direction   = "in"
    protocol    = "tcp"
    port        = "22"
    source_ips  = var.admin_cidrs
  }
  rule {
    description = "Kubernetes API (admin)"
    direction   = "in"
    protocol    = "tcp"
    port        = "6443"
    source_ips  = var.admin_cidrs
  }
  rule {
    description = "ICMP"
    direction   = "in"
    protocol    = "icmp"
    source_ips  = ["0.0.0.0/0", "::/0"]
  }
}

# Token del cluster: vive solo en el state (local, ignorado por git).
resource "random_password" "k3s_token" {
  length  = 48
  special = false
}

# IP publica reservada antes de crear el server, para usarla en --tls-san.
resource "hcloud_primary_ip" "server" {
  name        = "${var.cluster_name}-server-ipv4"
  type        = "ipv4"
  location    = var.location
  auto_delete = false
  labels      = local.labels
}

resource "hcloud_server" "server" {
  name         = "${var.cluster_name}-server"
  image        = "ubuntu-24.04"
  server_type  = var.server_type_server
  location     = var.location
  ssh_keys     = [hcloud_ssh_key.admin.id]
  firewall_ids = [hcloud_firewall.main.id]
  labels       = merge(local.labels, { role = "server" })

  public_net {
    ipv4_enabled = true
    ipv4         = hcloud_primary_ip.server.id
    ipv6_enabled = true
  }

  network {
    network_id = hcloud_network.main.id
    ip         = local.server_private_ip
  }

  user_data = templatefile("${path.module}/cloud-init/server.yaml.tftpl", {
    k3s_version = var.k3s_version
    k3s_token   = random_password.k3s_token.result
    private_ip  = local.server_private_ip
    public_ip   = hcloud_primary_ip.server.ip_address
  })

  depends_on = [hcloud_network_subnet.main]
}

resource "hcloud_server" "agent" {
  count        = var.agent_count
  name         = "${var.cluster_name}-agent-${count.index + 1}"
  image        = "ubuntu-24.04"
  server_type  = var.server_type_agent
  location     = var.location
  ssh_keys     = [hcloud_ssh_key.admin.id]
  firewall_ids = [hcloud_firewall.main.id]
  labels       = merge(local.labels, { role = "agent" })

  network {
    network_id = hcloud_network.main.id
    ip         = local.agent_private_ips[count.index]
  }

  user_data = templatefile("${path.module}/cloud-init/agent.yaml.tftpl", {
    k3s_version = var.k3s_version
    k3s_token   = random_password.k3s_token.result
    server_ip   = local.server_private_ip
    private_ip  = local.agent_private_ips[count.index]
  })

  depends_on = [hcloud_server.server]
}
