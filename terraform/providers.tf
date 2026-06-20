terraform {
  # backend "azurerm" {} # Commenté pour l'instant : on l'activera quand on créera le Storage Account pour le state
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}
