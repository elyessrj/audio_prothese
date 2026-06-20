# 🏥 AudioProthèse+ — Documentation Infrastructure (MVP)

Ce répertoire contient l'ensemble du code d'Infrastructure-as-Code (IaC) et de gestion des configurations pour le projet **AudioProthèse+**. L'infrastructure déploie une architecture hybride hautement sécurisée combinant un cluster managé dans le Cloud et une zone de simulation On-Premise dédiée au Plan de Reprise d'Activité (PRA), le tout optimisé pour respecter un budget strict de 85 $ (Azure Student).

**Pilote de l'infrastructure :** Zaafir (M1)
**Périmètre :** Terraform, Ansible, Réseau Hybride, FinOps & Sauvegardes MinIO.

---

## 🏗️ Architecture Globale de la Solution

L'architecture est entièrement automatisée et isolée au sein d'un réseau virtuel unique, segmenté logiquement pour simuler l'interconnexion entre le Cloud public et un centre médical local.

* **Zone Cloud Public (Azure) :** Héberge le cluster AKS (Azure Kubernetes Service) exécutant l'application santé critique (*OpenEMR*).
* **Zone On-Premise Simulée (Azure VM) :** Une machine virtuelle isolée configurée comme serveur local de stockage (MinIO) pour centraliser les sauvegardes externalisées.
* **Provisioning & Configuration :** Terraform pour l'infrastructure, Ansible pour le durcissement système et le déploiement applicatif sur la VM.

### Schéma détaillé

```text
                         ┌─────────────────────────────────┐
                         │         GitHub Actions           │
                         │  OIDC configuré (pas de pipeline │
                         │      build/test/deploy actif)    │
                         └────────────────┬──────────────────┘
                                          │
                                          ▼
┌────────────────────────────────────────────────────────────────────────────────┐
│  Resource Group : rg-audioprothese-dev (région polandcentral)                  │
│                                                                                  │
│  ┌────────────────────────────────────────────────────────────────────────┐   │
│  │                          VNET (10.0.0.0/8)                              │   │
│  │                                                                          │   │
│  │  ┌──────────────────────────────┐   ┌──────────────────────────────┐   │   │
│  │  │  Subnet AKS (10.240.0.0/16)   │   │ Subnet On-Premise (10.241.0.0/16)│  │
│  │  │  ┌──────────────────────────┐ │   │  ┌──────────────────────────┐ │   │   │
│  │  │  │  NSG dédié AKS           │ │   │  │  NSG dédié on-premise     │ │   │   │
│  │  │  └────────────┬─────────────┘ │   │  └────────────┬─────────────┘ │   │   │
│  │  │               ▼                │   │               ▼                │   │
│  │  │  ┌──────────────────────────┐ │   │  ┌──────────────────────────┐ │   │   │
│  │  │  │  Cluster AKS             │ │   │  │  VM On-Premise            │ │   │   │
│  │  │  │  1 nœud Standard_B2s_v2  │ │   │  │  Standard_B2s              │ │   │   │
│  │  │  └────────────┬─────────────┘ │   │  └────────────┬─────────────┘ │   │   │
│  │  │               ▼                │   │               ▼                │   │
│  │  │  ┌──────────────────────────┐ │   │  ┌──────────────────────────┐ │   │   │
│  │  │  │  OpenEMR                 │ │   │  │  MinIO                     │ │   │   │
│  │  │  │  + MySQL/MariaDB intégré │ │   │  │  API :9000 / Console :9001 │ │   │   │
│  │  │  └──────────────────────────┘ │   │  └──────────────────────────┘ │   │   │
│  │  │  ┌──────────────────────────┐ │   │               ▲                │   │   │
│  │  │  │  Pod test minio/mc       │ │───┼───────────────┘ Flux PRA (S3)  │   │   │
│  │  │  │  (validation flux PRA)   │ │   │                                │   │   │
│  │  │  └──────────────────────────┘ │   │                                │   │   │
│  │  └──────────────────────────────────┘   └──────────────────────────────────┘   │
│  │                                                ▲                            │   │
│  │                                                │ SSH -k -K (Ansible)        │   │
│  │                                    ┌───────────┴────────────┐               │   │
│  │                                    │  Ansible (durcissement, │               │   │
│  │                                    │  installation MinIO)    │               │   │
│  │                                    └──────────────────────────┘             │   │
│  └────────────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────────────┘
```

**Lecture du schéma :**
1. **Resource Group** : toutes les ressources (réseau, AKS, VM) sont regroupées dans `rg-audioprothese-dev`, ce qui simplifie la facturation, le nettoyage et l'application de tags FinOps.
2. **CI/CD (état actuel)** : GitHub Actions est configuré pour s'authentifier auprès d'Azure par fédération OIDC (zéro secret stocké), mais **aucun pipeline de build/test/déploiement automatisé n'est encore implémenté** — l'OIDC pose seulement les fondations pour une future intégration continue.
3. **Isolation réseau à deux niveaux** : chaque sous-réseau possède son propre NSG (`nsg-aks` et `nsg-onprem`), garantissant qu'une règle ouverte côté AKS ne s'applique jamais à la VM on-premise et inversement.
4. **OpenEMR** s'exécute dans le cluster AKS avec sa base de données MySQL/MariaDB **intégrée au même pod/conteneur** (pas de service de base de données externe pour ce MVP).
5. **MinIO** tourne exclusivement **sur la VM On-Premise isolée**, jamais sur AKS — c'est le serveur de stockage cible du PRA.
6. Ansible se connecte en SSH à la VM On-Premise (mots de passe demandés interactivement, jamais stockés) pour durcir le système et déployer MinIO.
7. Le flux PRA est validé manuellement depuis un pod éphémère `minio/mc` à l'intérieur du cluster AKS, qui pousse un fichier de test vers MinIO via le réseau interne — confirmant qu'AKS est bien le **client** du flux de sauvegarde, et la VM isolée le **serveur** de destination.

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
* **Isolation Réseau Stricte :** Création de deux sous-réseaux distincts (`snet-aks` en `10.240.0.0/16` et `snet-onprem` en `10.241.0.0/16`), **chacun protégé par son propre Network Security Group** (`nsg-aks` et `nsg-onprem`) pour filtrer les flux et éviter qu'une règle ouverte d'un côté n'expose l'autre.
* **Sécurité Identity & OIDC :** Activation de l'émetteur OIDC (`oidc_issuer_enabled = true`) permettant un raccordement futur de la CI/CD par fédération d'identité, garantissant une politique Zéro Secret en clair dans les dépôts Git. *(À ce stade, seule cette fédération d'identité est en place ; aucun pipeline de build/test/déploiement automatisé n'est encore branché dessus.)*

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

> ⚠️ Les valeurs ci-dessous sont propres à chaque déploiement (elles changent à chaque nouveau compte Azure ou `terraform apply`). Récupère les tiennes avec `terraform output` à la fin du provisioning et reporte-les dans ta copie locale de ce document — ne les commite jamais dans Git.

| Ressource | Valeur (exemple de format) |
|---|---|
| Resource Group | `rg-audioprothese-dev` |
| Région | `polandcentral` |
| Cluster K8s | `aks-audioprothese-dev` |
| IP Publique VM On-Premise | `<VM_PUBLIC_IP>` |

Pour afficher l'IP publique générée par Terraform sans avoir à fouiller le state :
```bash
terraform output vm_onprem_public_ip
```

---

## 🔒 Zoom sur la VM On-Premise (Isolation & Connexion)

La VM On-Premise simule un centre médical distant. Elle est volontairement **isolée du reste de l'infrastructure** : elle ne fait pas partie du cluster AKS, ne partage aucun rôle IAM avec lui, et tout flux entrant/sortant passe par des règles explicites.

### Isolation réseau (NSG)

* La VM réside dans son propre sous-réseau `snet-onprem` (`10.241.0.0/16`), distinct du sous-réseau AKS (`10.240.0.0/16`). Aucune route n'est ouverte par défaut entre les deux : seules les règles NSG listées ci-dessous autorisent un flux. Le subnet AKS dispose lui aussi de son propre NSG (`nsg-aks`), distinct de celui de la VM — l'isolation est symétrique, pas seulement côté on-premise.
* Le NSG attaché à la VM (`nsg-onprem`) n'autorise que les ports strictement nécessaires :

| Port | Protocole | Source | Usage |
|---|---|---|---|
| 22 | TCP | `<TON_IP_PUBLIQUE>/32` | Administration SSH (Ansible) |
| 9000 | TCP | `VirtualNetwork` (interne au VNET) | API MinIO — flux de sauvegarde depuis AKS |
| 9001 | TCP | `<TON_IP_PUBLIQUE>/32` | Console web MinIO (administration uniquement) |

> ⚠️ **À adapter avec le nouveau compte :** par défaut un déploiement Terraform "from scratch" ouvre souvent SSH et la console MinIO sur `0.0.0.0/0` (Internet) pour simplifier les tests. **Restreins ces deux règles à ta propre IP publique** (`curl ifconfig.me` pour la connaître) avant toute démo ou dépôt du code, le port 9000 n'a lui aucune raison de sortir du VNET.
* Aucun autre port n'est exposé : pas de RDP, pas d'accès direct à la base de données, pas de port Docker exposé publiquement en dehors de MinIO.

### Connexion à la VM

* **Méthode d'authentification :** mot de passe (saisi interactivement à l'`apply` Terraform, jamais stocké en clair dans le code — cf. section Secrets ci-dessous). Une migration vers une authentification par clé SSH est recommandée si la VM doit rester en place au-delà de la phase de test (voir note en fin de section).
* **Utilisateur d'administration :** `<ADMIN_USER>` (à définir dans `terraform.tfvars`, remplace le `zaafir` codé en dur du POC précédent par un nom générique ou ton propre identifiant pour ce nouveau déploiement).
* **Commande de connexion manuelle :**
```bash
ssh <ADMIN_USER>@<VM_PUBLIC_IP>
```
* Ansible se connecte avec les mêmes identifiants via les flags `-k` (mot de passe SSH) et `-K` (mot de passe sudo), demandés interactivement à chaque exécution du playbook — aucun secret n'est donc présent dans `inventory.ini` ni dans le code versionné.

> 💡 **Recommandation :** pour un usage au-delà du MVP, remplace l'authentification par mot de passe par une paire de clés SSH (`ssh-keygen`, puis injection de la clé publique via `admin_ssh_key` dans la ressource Terraform de la VM). Cela permet de désactiver `PasswordAuthentication` dans `sshd_config` et de supprimer `sshpass` des prérequis.

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
<VM_PUBLIC_IP> ansible_user=<ADMIN_USER>
```

> Remplace `<VM_PUBLIC_IP>` et `<ADMIN_USER>` par les valeurs réelles de ton déploiement (voir section [Zoom sur la VM On-Premise](#-zoom-sur-la-vm-on-premise-isolation--connexion)). Ce fichier contenant une IP réelle, garde-le hors de Git (ajoute-le à `.gitignore`) ou versionne uniquement un `inventory.ini.example`.

### Exécution du Playbook

Exécuter la configuration automatisée. Les drapeaux `-k` et `-K` demandent interactivement les mots de passe de connexion et de privilèges pour ne stocker aucun secret dans le code :

```bash
ansible-playbook -i inventory.ini playbook-onprem.yml -k -K
```

### Validation du Service MinIO

Une fois le déploiement Ansible complété avec succès, la console d'administration S3-compatible est accessible depuis ton IP autorisée (cf. règles NSG ci-dessus — l'accès n'est plus ouvert à tout Internet) :

* **URL de l'interface :** `http://<VM_PUBLIC_IP>:9001`
* **Port API (Flux de sauvegarde) :** `9000`
* **Identifiants :** définis dans `playbook-onprem.yml` / variables Ansible (`<MINIO_ROOT_USER>` / `<MINIO_ROOT_PASSWORD>`), voir section Secrets ci-dessous. Ne pas garder les identifiants par défaut du POC initial.

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
mc alias set mon-minio http://<VM_PUBLIC_IP>:9000 <MINIO_ROOT_USER> <MINIO_ROOT_PASSWORD>

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

---

## 🔑 Gestion des Secrets

Ce document ne contient volontairement **aucune valeur réelle** (IP, mot de passe, utilisateur). Voici où trouver/définir chaque secret pour ton propre déploiement, et comment les manipuler sans les exposer dans Git.

| Placeholder | Où il est défini | Comment le récupérer |
|---|---|---|
| `<VM_PUBLIC_IP>` | Générée par Azure à l'`apply` Terraform | `terraform output vm_onprem_public_ip` |
| `<ADMIN_USER>` | `terraform.tfvars` (variable `admin_username`) | Choisi par toi avant l'`apply` |
| `<TON_IP_PUBLIQUE>` | N/A — ton poste local | `curl ifconfig.me` |
| `<MINIO_ROOT_USER>` / `<MINIO_ROOT_PASSWORD>` | Variables du playbook Ansible (`playbook-onprem.yml` ou `group_vars/onpremise.yml`) | Définies par toi avant le run Ansible |
| Mot de passe VM (`az vm` admin) | Saisi interactivement à `terraform apply` | Jamais stocké — à conserver dans un gestionnaire de mots de passe si besoin de le réutiliser |

### Bonnes pratiques pour ce nouveau déploiement

* **Ne commite jamais** `inventory.ini`, `terraform.tfvars`, ni aucun fichier contenant une IP ou un mot de passe réel. Ajoute-les à `.gitignore` :
```text
terraform.tfvars
inventory.ini
*.tfstate
*.tfstate.backup
```
* Fournis des fichiers d'exemple versionnés (`terraform.tfvars.example`, `inventory.ini.example`) avec uniquement des placeholders, sur le modèle de ceux utilisés dans ce README.
* Change systématiquement les identifiants MinIO par défaut avant toute démo ou mise en ligne, même temporaire.
* Si ce dépôt a déjà été poussé avec les anciennes valeurs en clair (IP `74.248.19.207`, utilisateur `zaafir`, mot de passe MinIO `SuperSecretPassword123!`), considère-les comme compromises : régénère la VM avec de nouveaux identifiants plutôt que de simplement changer le mot de passe, et purge l'historique Git si nécessaire (`git filter-repo` ou équivalent).
