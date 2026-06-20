# Création du Groupe de Ressources
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    Project     = "AudioProthesePlus"
    Environment = "MVP-Dev"
    ManagedBy   = "Terraform"
    Owner       = "Zaafir-M1"
  }
}

# Création du Réseau Virtuel (Fondation pour l'isolation et la simulation On-Premise)
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-audioprothese"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/8"]
  tags                = azurerm_resource_group.rg.tags
}

# Sous-réseau dédié pour AKS
resource "azurerm_subnet" "aks_subnet" {
  name                 = "snet-aks"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.240.0.0/16"]
}

# Création du cluster AKS managé
resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.aks_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "aksaudioprothese"
  
  sku_tier            = "Free" # FinOps: Garantie de ne pas payer le Control Plane

  # Sécurité : Permet l'authentification sans secret depuis GitHub Actions
  oidc_issuer_enabled       = true
  workload_identity_enabled = true 

  # Configuration des machines (nœuds) du cluster
  default_node_pool {
    name           = "default"
    node_count     = 1 # FinOps: 1 seul noeud au lieu de 2
    vm_size        = "Standard_B2s_v2" # Taille standard et économique
    vnet_subnet_id = azurerm_subnet.aks_subnet.id
  }

  # Gestion automatique de l'identité par Azure
  identity {
    type = "SystemAssigned"
  }

  # Configuration réseau (Sécurité by design)
  network_profile {
    network_plugin = "azure"
    network_policy = "calico"
  }

  tags = azurerm_resource_group.rg.tags
}


# ==========================================
# SIMULATION ON-PREMISE (VM MinIO)
# ==========================================

# Sous-réseau dédié pour la simulation On-Premise (Isolé de l'AKS)
resource "azurerm_subnet" "onprem_subnet" {
  name                 = "snet-onprem"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.241.0.0/16"] # Adressage différent de l'AKS (10.240.x.x)
}

# IP Publique pour te connecter depuis le portail Azure ou ton poste
resource "azurerm_public_ip" "onprem_pip" {
  name                = "pip-onprem-sim"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  
  # Modifications requises par Azure : SKU Standard et Static
  allocation_method   = "Static"
  sku                 = "Standard" 
  
  tags                = azurerm_resource_group.rg.tags
}

# Interface réseau de la VM
resource "azurerm_network_interface" "onprem_nic" {
  name                = "nic-onprem-sim"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.onprem_subnet.id # <--- MODIFICATION ICI
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.onprem_pip.id
  }
}

# La Machine Virtuelle (Serveur de sauvegarde local)
resource "azurerm_linux_virtual_machine" "onprem_vm" {
  name                = "vm-onprem-sim"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_B2s_v2" # Taille demandée
  admin_username      = "zaafir"
  
  # Configuration pour connexion directe par mot de passe via le portail
  disable_password_authentication = false
  admin_password                  = var.vm_admin_password
  
  network_interface_ids = [
    azurerm_network_interface.onprem_nic.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
  
  tags = azurerm_resource_group.rg.tags
}

# ==========================================
# SÉCURITÉ RÉSEAU (NSG On-Premise)
# ==========================================

resource "azurerm_network_security_group" "onprem_nsg" {
  name                = "nsg-onprem-sim"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = azurerm_resource_group.rg.tags

  # Règle pour autoriser la connexion SSH
  security_rule {
    name                       = "Allow-SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*" # En prod réelle, on limiterait à ton IP personnelle
    destination_address_prefix = "*"
  }

  # Règle pour autoriser l'accès à l'interface web de MinIO
  security_rule {
    name                       = "Allow-MinIO"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["9000", "9001"]
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Attachement du pare-feu à l'interface réseau de la VM
resource "azurerm_network_interface_security_group_association" "onprem_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.onprem_nic.id
  network_security_group_id = azurerm_network_security_group.onprem_nsg.id
}
