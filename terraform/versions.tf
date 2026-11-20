terraform {
  required_version = ">= 1.5"

  # Local state. CI stores it on vm-runner (VM 104) via:
  #   terraform init -backend-config="path=/var/lib/homelab-state/terraform.tfstate"
  backend "local" {}

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.123"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "proxmox" {
  endpoint  = var.pve_endpoint
  api_token = var.pve_api_token
  insecure  = true # Proxmox uses a self-signed certificate by default
}
