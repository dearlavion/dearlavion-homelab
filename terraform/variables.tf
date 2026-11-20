variable "pve_endpoint" {
  description = "Proxmox web/API address, e.g. https://192.168.8.50:8006/"
  type        = string
}

variable "pve_api_token" {
  description = "API token 'user@realm!tokenid=secret' (written by the Ansible playbook)"
  type        = string
  sensitive   = true
}

variable "pve_node" {
  description = "Proxmox node name (shown in the web UI tree, usually 'pve')"
  type        = string
  default     = "pve"
}

variable "template_id" {
  description = "VM ID of the Ubuntu cloud-init template"
  type        = number
  default     = 9000
}

variable "vm_datastore" {
  description = "Storage for VM disks"
  type        = string
  default     = "local-lvm"
}

variable "net_prefix" {
  description = "First three parts of your LAN, e.g. 192.168.8 (VM ID becomes the last part)"
  type        = string
}

variable "gateway" {
  description = "Your router IP, used as gateway and DNS"
  type        = string
}

variable "ssh_public_key_path" {
  description = "Public key allowed to log in to the VMs as 'ubuntu'"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "extra_ssh_keys" {
  description = "More public keys allowed to log in to the VMs (e.g. your laptop)"
  type        = list(string)
  default     = []
}
