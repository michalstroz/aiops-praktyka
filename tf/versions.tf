terraform {
  required_version = ">= 1.16"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.3"
    }
  }

  # Stan lokalnie w tf/terraform.tfstate (plik w .gitignore).
  backend "local" {
    path = "terraform.tfstate"
  }
}
