output "resource_group_name" {
  description = "Nom du Resource Group"
  value       = azurerm_resource_group.rg.name
}

output "kubernetes_cluster_name" {
  description = "Nom du Cluster AKS"
  value       = azurerm_kubernetes_cluster.aks.name
}

output "aks_oidc_issuer_url" {
  description = "URL OIDC de l'AKS (à transmettre à M2 pour GitHub Actions)"
  value       = azurerm_kubernetes_cluster.aks.oidc_issuer_url
}

output "kube_config_command" {
  description = "Commande pour récupérer les credentials AKS localement"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.rg.name} --name ${azurerm_kubernetes_cluster.aks.name}"
}

output "onprem_vm_public_ip" {
  description = "IP publique de la VM simulant le On-Premise"
  value       = azurerm_linux_virtual_machine.onprem_vm.public_ip_address
}
