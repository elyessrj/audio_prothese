# 🏥 AudioProthèse+ — Documentation Infrastructure (MVP)

Ce répertoire contient l'ensemble du code d'Infrastructure-as-Code (IaC) et de gestion des configurations pour le projet **AudioProthèse+**. L'infrastructure déploie une architecture hybride hautement sécurisée combinant un cluster managé dans le Cloud et une zone de simulation On-Premise dédiée au Plan de Reprise d'Activité (PRA), le tout optimisé pour respecter un budget strict de 85 $ (Azure Student).

**Pilote de l'infrastructure :** Zaafir (M1)
**Périmètre :** Terraform, Ansible, Réseau Hybride, FinOps & Sauvegardes MinIO.

---

## 🏗️ Architecture Globale de la Solution

L'architecture est entièrement automatisée et isolée au sein d'un réseau virtuel unique, segmenté logiquement pour simuler l'interconnexion entre le Cloud public et un centre médical local.

* **Zone Cloud Public (Azure) :** Héberge le cluster AKS (Azure Kubernetes Service) exécutant l'application santé critique (*OpenEMR*) et la pile d'observabilité.
* **Zone On-Premise Simulée (Azure VM) :** Une machine virtuelle isolée configurée comme serveur local de stockage pour centraliser les sauvegardes externalisées.

```text
[GitHub Actions (CI/CD)] 
       │ (Authentification sécurisée OIDC)
       ▼
 ┌────────────────────────────────────────────────────────┐
 │                 VNET (10.0.0.0/8)                      │
 │                                                        │
 │  ┌───────────────────────┐    ┌─────────────────────┐  │
 │  │   Subnet AKS          │    │ Subnet On-Premise   │  │
 │  │   (10.240.0.0/16)     │    │ (10.241.0.0/16)     │  │
 │  │                       │    │                     │  │
 │  │  ┌─────────────────┐  │    │  ┌───────────────┐  │  │
 │  │  │   Cluster AKS   │  │    │  │ VM On-Premise │  │  │
 │  │  │ (1 Node B2s_v2) │  │    │  │ (Standard_B2s)│  │  │
 │  │  └────────┬────────┘  │    │  └───────┬───────┘  │  │
 │  └───────────┼───────────┘    └──────────┼──────────┘  │
 └──────────────┼───────────────────────────┼─────────────┘
                │       Flux PRA (S3)       │
                └───────────────────────────┘
```

---

## 🛠️ Prérequis

Avant de lancer le déploiement, assure-toi de disposer des outils suivants installés localement :

* **Azure CLI** (connecté au compte étudiant via `az login`)
* **Terraform** (>= 1.5.0)
* **Ansible**
* L'utilitaire **sshpass** (requis par Ansible pour l'authentification par mot de passe : `sudo apt install sshpass -y`)

---

## 🚀 Étape 1 : Provisioning Cloud avec Terraform

Le dossier `terraform/` initialise l'infrastructure réseau, le cluster Kubernetes et la machine de simulation.

### Spécifications Techniques & Justifications (ADR)

* **Cluster AKS Free Tier & Nœud Unique :** Choix d'un modèle économique sans facturation du Control Plane, limité à 1 seul nœud `Standard_B2s_v2` pour valider l'industrialisation sans saturer les crédits Azure.
* **Isolation Réseau Stricte :** Création de deux sous-réseaux distincts (`snet-aks` en `10.240.0.0/16` et `snet-onprem` en `10.241.0.0/16`). La VM On-Premise possède son propre Network Security Group (NSG) pour filtrer les flux et éviter les conflits avec les politiques de sécurité d'AKS.
* **Sécurité Identity & OIDC :** Activation de l'émetteur OIDC (`oidc_issuer_enabled = true`) permettant un raccordement de la CI/CD par fédération d'identité, garantissant une politique Zéro Secret en clair dans les dépôts Git.

### Déploiement

1. Initialiser le répertoire de travail :
```bash
terraform init
```

2. Générer et valider le plan d'exécution :
```bash
terraform plan -out=tfplan
```

3. Appliquer l'infrastructure (un mot de passe sécurisé pour la VM vous sera demandé à l'exécution) :
```bash
terraform apply tfplan
```

### Données de Sortie Constatées (Outputs)

| Ressource | Valeur |
|---|---|
| Resource Group | `rg-audioprothese-dev` |
| Région | `polandcentral` |
| Cluster K8s | `aks-audioprothese-dev` |
| IP Publique VM On-Premise | `74.248.19.207` |

---

## ⚙️ Étape 2 : Configuration et Déploiement du PRA avec Ansible

Une fois la VM en ligne, Ansible automatise le durcissement du système, l'installation du moteur Docker et le déploiement du serveur de stockage objet MinIO.

### Configuration du projet Ansible

Le fichier `ansible.cfg` est configuré à la racine pour désactiver la vérification stricte de la clé d'hôte, facilitant les cycles de destruction/reconstruction de l'environnement de test :

```ini
[defaults]
host_key_checking = False
```

L'inventaire cible l'IP provisionnée par Terraform (`inventory.ini`) :

```ini
[onpremise]
74.248.19.207 ansible_user=zaafir
```

### Exécution du Playbook

Exécuter la configuration automatisée. Les drapeaux `-k` et `-K` demandent interactivement les mots de passe de connexion et de privilèges pour ne stocker aucun secret dans le code :

```bash
ansible-playbook -i inventory.ini playbook-onprem.yml -k -K
```

### Validation du Service MinIO

Une fois le déploiement Ansible complété avec succès, la console d'administration S3-compatible est accessible publiquement :

* **URL de l'interface :** `http://74.248.19.207:9001`
* **Port API (Flux de sauvegarde) :** `9000`
* **Identifiants par défaut :** `admin_audioprothese` / `SuperSecretPassword123!`

---

## 🛡️ Vérification Opérationnelle du PRA (Flux Cloud ↔ On-Prem)

Pour valider la connectivité réseau et la viabilité du Plan de Reprise d'Activité avant l'intégration applicative, un test d'injection de données est réalisé directement depuis l'intérieur du cluster AKS vers le MinIO On-Premise.

1. **Récupérer les accès du cluster AKS localement :**
```bash
az aks get-credentials --resource-group rg-audioprothese-dev --name aks-audioprothese-dev --overwrite-existing
```

2. **Instancier un Pod de test éphémère embarquant le client MinIO (`mc`) :**
```bash
kubectl run test-pra -i --tty --image=minio/mc --restart=Never -- sh
```

3. **Exécuter les commandes de transfert dans le Shell du Pod :**
```bash
# Associer l'alias réseau vers la VM On-Premise
mc alias set mon-minio http://74.248.19.207:9000 admin_audioprothese SuperSecretPassword123!

# Créer une fausse empreinte de base de données patient
echo "Simulation Dump SQL AudioProthese v1" > dump_test.sql

# Envoyer le fichier vers le bucket sécurisé
mc cp dump_test.sql mon-minio/db-backups/
```

4. Vérifier la présence du fichier `dump_test.sql` sur la console Web de MinIO. Le flux hybride est ainsi validé.

---

## 📉 Stratégie FinOps (Gestion du Budget 85 $)

L'infrastructure utilise des ressources actives facturées à l'heure. Pour maximiser la durée de vie du budget étudiant de 85 $, **toutes les ressources de calcul doivent être éteintes en dehors des sessions de développement et de démonstration**.

### Commandes de coupure de fin de session (Stop)

```bash
# Arrêt du cluster AKS (Conserve la configuration, stoppe la facturation des nœuds)
az aks stop --name aks-audioprothese-dev --resource-group rg-audioprothese-dev

# Libération de la VM On-Premise (Désalloue le CPU/RAM, stoppe la facturation de l'instance)
az vm deallocate --resource-group rg-audioprothese-dev --name vm-onprem-sim
```

### Commandes de reprise de session (Start)

```bash
# Redémarrage de la VM de sauvegarde
az vm start --resource-group rg-audioprothese-dev --name vm-onprem-sim

# Redémarrage du cluster Kubernetes
az aks start --name aks-audioprothese-dev --resource-group rg-audioprothese-dev
```
