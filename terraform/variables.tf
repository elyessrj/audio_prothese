variable "resource_group_name" {
  type        = string
  description = "Le nom du groupe de ressources"
  default     = "rg-audioprothese-dev"
}

variable "location" {
  type        = string
  description = "La région Azure"
  default     = "polandcentral" # Proche et économique
}

variable "aks_name" {
  type        = string
  description = "Le nom du cluster Kubernetes"
  default     = "aks-audioprothese-dev"
}

variable "vm_admin_password" {
  type        = string
  description = "Mot de passe administrateur pour la VM On-Premise (Saisi à l'exécution)"
  sensitive   = true
}
