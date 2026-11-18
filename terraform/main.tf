# The four VMs. Change sizes here and run `terraform apply`.
# Budget: 15 + 20 + 20 + 10 = 65G (+3.5G template) of 72.7G local-lvm
#         3 + 3.5 + 3.5 + 1.5 = 11.5 GB of 16 GB RAM
locals {
  vms = {
    "k8s-cp" = { id = 100, cores = 2, memory = 3072, disk = 15, order = 1, up_delay = 30, group = "control_plane" }
    "k8s-w1" = { id = 101, cores = 2, memory = 3584, disk = 20, order = 2, up_delay = 0, group = "workers" }
    "k8s-w2" = { id = 102, cores = 2, memory = 3584, disk = 20, order = 2, up_delay = 0, group = "workers" }
    "devops" = { id = 103, cores = 1, memory = 1536, disk = 10, order = 3, up_delay = 0, group = "tools" }
  }
}

resource "proxmox_virtual_environment_vm" "vm" {
  for_each = local.vms

  name      = each.key
  vm_id     = each.value.id
  node_name = var.pve_node
  on_boot   = true
  started   = true

  # Full copy of template 9000
  clone {
    vm_id        = var.template_id
    full         = true
    datastore_id = var.vm_datastore
  }

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  # floating = 0 -> ballooning off (Kubernetes needs fixed RAM)
  memory {
    dedicated = each.value.memory
    floating  = 0
  }

  disk {
    datastore_id = var.vm_datastore
    interface    = "scsi0"
    size         = each.value.disk
    discard      = "on"
    ssd          = true
    iothread     = true
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  agent {
    enabled = true
  }

  operating_system {
    type = "l26"
  }

  serial_device {}

  vga {
    type = "serial0"
  }

  startup {
    order    = each.value.order
    up_delay = each.value.up_delay
  }

  # Cloud-init: user, SSH key, static IP, plus the vendor snippet
  initialization {
    datastore_id = var.vm_datastore
    interface    = "ide2"

    ip_config {
      ipv4 {
        address = "${var.net_prefix}.${each.value.id}/24"
        gateway = var.gateway
      }
    }

    dns {
      servers = [var.gateway]
    }

    user_account {
      username = "ubuntu"
      keys     = concat([trimspace(file(pathexpand(var.ssh_public_key_path)))], var.extra_ssh_keys)
    }

    vendor_data_file_id = "local:snippets/vendor.yaml"
  }
}

# Writes ansible/inventory/k8s.ini so Ansible knows the new VMs
resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../ansible/inventory/k8s.ini"
  file_permission = "0644"
  content = templatefile("${path.module}/templates/k8s-inventory.ini.tftpl", {
    vms        = local.vms
    net_prefix = var.net_prefix
  })
}
