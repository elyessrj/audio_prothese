# CLAUDE.md — AudioProthèse+ · Infrastructure DevOps hybride

> Fichier de contexte du projet, lu automatiquement par Claude Code et destiné à toute personne (ou IA) qui travaille sur le repo. **Lis-le en entier avant de produire du code.**

---

## 1. Contexte

**AudioProthèse+** est un réseau national de centres d'audioprothésistes (projet d'étude M2 DevOps — SUP DE VINCI). L'entreprise exploite des applications métiers critiques (CRM, prise de rendez-vous, dossiers patients, téléconsultation) sur une infrastructure **hybride : cloud + serveurs on-premise**.

**Problématique à résoudre :**
- Environnements hétérogènes, peu automatisés, difficiles à maintenir.
- Déploiements semi-manuels → erreurs et retards.
- Sécurité et résilience insuffisantes (accès, secrets, conformité).
- Supervision fragmentée, pas d'observabilité centralisée.
- Manque d'industrialisation → coûts et consommation énergétique élevés.

**Enjeu métier :** disponibilité, sécurité et scalabilité pour un réseau **santé sensible**, dans le respect du **RGPD et de l'HDS** (Hébergeur de Données de Santé).

Ce contexte est fictif mais sert de fil rouge : chaque choix technique doit pouvoir être **justifié** par rapport à ces contraintes (santé, hybride, conformité).

---

## 2. Objectif & périmètre du MVP

Industrialiser une **chaîne DevOps hybride reproductible et sécurisée** : IaC → conteneurisation → orchestration K8s → CI/CD GitOps → observabilité → sécurité → PRA → Green IT.

**Principe directeur du périmètre : tranche verticale fine.** On vise **l'application la plus simple possible qui traverse réellement les 10 étapes**, pas une appli riche. L'objectif est de démontrer la *chaîne complète*, pas la profondeur fonctionnelle.

> ⚠️ Périmètre fonctionnel de l'appli **à figer au cadrage** (voir §11) : une API santé (1–2 endpoints, ex. agenda de RDV) + un front minimal + une base de données. La donnée patient sert de justification à la partie on-premise / HDS.

---

## 3. Équipe & rôles

| Rôle | Responsable | Périmètre principal |
|------|-------------|---------------------|
| **M1** | **Zaafir** | IaC & Cloud — Terraform, Ansible, provisioning cloud + on-prem, schéma infra, sauvegardes/MinIO |
| **M2** | **Elyess** | CI/CD & GitOps — workflows GitHub Actions, ArgoCD, Trivy dans le pipeline |
| **M3** | **Anis** | Orchestration & Conteneurs — Docker, Kubernetes, Helm, scalabilité/HA, autoscaling, restauration des workloads |
| **M4** | **Adame** | Sécurité & Observabilité + **FinOps** — Vault/secrets, RBAC, TLS, Prometheus/Grafana/logs, dashboards Green IT, analyse de coûts |

> Quand tu génères du code ou de la doc, **respecte le périmètre du rôle concerné** et place les fichiers dans le bon dossier (voir §6). Ne déborde pas sur le scope d'un autre membre sans le signaler.

---

## 4. Stack technique

Stack **recommandé par le cahier des charges** (donc défendable tel quel) :

| Domaine | Outil retenu | Note |
|---------|--------------|------|
| IaC (provisioning) | **Terraform** | modules réutilisables + environnements dev/prod |
| IaC (configuration) | **Ansible** | playbooks + rôles |
| Conteneurs | **Docker** | + docker-compose pour le dev local |
| Orchestration | **Kubernetes** | distribution → voir §10 (décision ouverte) |
| Packaging K8s | **Helm** | charts versionnés |
| CI/CD | **GitHub Actions** | build, tests, scan, push |
| Registry | **GHCR** (GitHub Container Registry) | images Docker du projet |
| Déploiement | **ArgoCD** (GitOps) | app-of-apps / ApplicationSets |
| Métriques | **kube-prometheus-stack** (Helm) | colonne vertébrale, dashboards Grafana attendus |
| Logs + traces | **OpenObserve** | unifié, backend **S3/MinIO**, requêtes langage naturel + serveur MCP |
| Secrets | **Vault** ou **SOPS/Sealed Secrets** | voir §10 |
| Scan vulnérabilités | **Trivy** + **Trivy Operator** | CI (M2) + scan continu in-cluster (M4) |
| Policies / admission | **Kyverno** | bloque pods privilégiés, images non conformes, etc. |
| Détection runtime | **Falco** | menaces à l'exécution (DaemonSet, CNCF) |
| TLS | **cert-manager** | émission/renouvellement auto des certificats |
| Stockage / backups | **MinIO** (S3-compatible) | backend objet partagé (backups + OpenObserve) |

**Règle d'or :** on n'introduit **aucun outil hors de ce tableau** sans validation d'équipe. Si une IA propose un outil non listé, elle doit le signaler explicitement comme une dérogation.

---

## 5. Architecture hybride (vue d'ensemble)

Flux cible :

```
Dev → GitHub (repo + Actions) → GHCR → [scan Trivy] → ArgoCD → Kubernetes → Observabilité (kube-prometheus-stack + OpenObserve)
                                                          │
                              ┌───────────────────────────┴───────────────────────────┐
                              │  CLOUD                          │  ON-PREMISE (simulé)  │
                              │  compute non sensible, CI/CD,   │  données patients     │
                              │  monitoring                     │  (justif. HDS)        │
                              └─────────────── lien sécurisé (VPN/WireGuard) ───────────┘
```

**Point d'attention n°1 du projet :** le **lien sécurisé cloud ↔ on-premise** (réseau, zones de confiance, flux). C'est la pièce la plus difficile et la première que le jury sondera. Elle doit être **conçue à l'étape 1** et avoir un propriétaire explicite (M1 + validation sécu M4). On-premise est **simulé** par une VM locale / un nœud K8s séparé.

---

## 6. Structure du repo (monorepo)

```
audioprothese-plus/
├── CLAUDE.md                 # ce fichier
├── README.md                 # démarrage rapide
├── docs/                     # archi, ADR (décisions), schémas, PRA/PCA, FinOps, Gantt
├── app/                      # [M3] appli santé
│   ├── api/                  #   API (endpoints)
│   ├── front/                #   front minimal
│   ├── Dockerfile
│   └── docker-compose.yml    #   dev local
├── infra/
│   ├── terraform/            # [M1] modules/ + environments/{dev,prod}/
│   └── ansible/              # [M1] playbooks/ + roles/
├── k8s/                      # [M3] manifests (base/ + overlays/) et charts Helm
├── argocd/                   # [M2] app-of-apps / ApplicationSets
├── .github/workflows/        # [M2] pipelines CI/CD (GitHub Actions)
├── security/                 # [M4] config Vault/SOPS, RBAC, TLS, policies
├── observability/            # [M4] Prometheus, dashboards Grafana, Loki, règles d'alerte
└── finops/                   # [M4] analyse de coûts, KPIs Green IT
```

---

## 7. Conventions

- **Langue :** documentation en **français**, code et identifiants en **anglais**.
- **Git :** branche par feature (`feat/m4-prometheus`, `fix/...`), pas de push direct sur `main`. MR/PR relue par au moins un autre membre.
- **Commits :** convention *Conventional Commits* (`feat:`, `fix:`, `docs:`, `chore:`, `ci:`, `refactor:`).
- **Décisions techniques :** chaque choix structurant fait l'objet d'un court **ADR** dans `docs/adr/` (contexte → décision → conséquences). Indispensable pour la « justification des choix » notée.
- **IaC :** rien n'est créé à la main. Toute ressource passe par Terraform/Ansible. Templates reproductibles.
- **Documentation continue :** on documente au fil de l'eau, pas à la fin.

---

## 8. Principes non négociables

1. **Aucun secret en clair.** Jamais de mot de passe / token / clé dans le code, les commits ou les manifests. C'est un projet **sécurité** : un secret leaké, c'est un point perdu et un mauvais exemple. → Vault / SOPS / variables CI protégées.
2. **Sécurité by design.** RBAC K8s, TLS, moindre privilège, traçabilité dès le départ — pas en rustine finale.
3. **GitOps.** L'état du cluster = ce qui est dans Git. Pas de `kubectl apply` manuel en prod ; on passe par ArgoCD.
4. **Terraform : jamais d'`apply` sans `plan` relu.** Toute IA doit présenter le `plan` et attendre validation avant d'appliquer.
5. **Reproductibilité.** Le projet doit être duplicable et réutilisable (consigne explicite de l'école). Tout doit pouvoir être recréé à partir de zéro depuis le repo.
6. **Green IT mesurable.** Les optimisations (autoscaling, choix d'outils légers) doivent être appuyées par des **KPIs réels** (CPU/RAM, coût), pas des affirmations.

---

## 9. Roadmap → rôles (résumé)

| Étape | Pilote | Sortie attendue |
|-------|--------|-----------------|
| 0 Cadrage | Équipe | Contexte, problématique, périmètre MVP |
| 1 Architecture | M1 (+M4 sécu) | Schéma hybride + justification + design du lien cloud/on-prem |
| 2 IaC | M1 | Terraform (plan+apply), playbooks Ansible |
| 3 Docker | M3 (+M2) | Image fonctionnelle, docker-compose local |
| 4 Kubernetes | M3 | Manifests/Helm, appli accessible |
| 5 CI/CD | M2 (+M4 Trivy) | workflow GitHub Actions vert, déploiement via ArgoCD |
| 6 Sécurité | M4 | Secrets gérés, RBAC, TLS |
| 7 Observabilité | M4 | Dashboards Grafana, logs centralisés, alertes |
| 8 PRA | M1 (backups) + M3 (workloads) | Sauvegardes testées, procédure de restauration |
| 9 Green IT + FinOps | M3 (autoscaling) + M4 (KPIs/coûts) | Analyse coûts cloud vs on-prem, KPIs énergétiques |
| 10 Livrables | Équipe | Doc technique + vidéo MVP + PDF individuels |

---

## 10. Décisions ouvertes (à trancher au kick-off)

Ces points ne sont **pas encore décidés** — ne les invente pas, demande ou propose un ADR :

- **Fournisseur cloud :** GCP Free Tier / Azure Student / AWS Educate. (À choisir selon crédits dispo et compétences de l'équipe.)
- **Distribution Kubernetes :** **K3s** proposé (léger, idéal hybride + budget étudiant, tourne sur VM cloud et nœud on-prem) vs managé (GKE/AKS, plus cher).
- **Secrets :** **Vault** (plus impressionnant, plus de setup) vs **SOPS/Sealed Secrets** (natif GitOps, plus simple à intégrer à ArgoCD).
- **Périmètre fonctionnel exact de l'appli** (endpoints, données).

**Décisions actées (M4) :** observabilité = **kube-prometheus-stack** (métriques) + **OpenObserve** (logs/traces, backend S3/MinIO) ; sécurité = **Trivy** + **Trivy Operator** + **Kyverno** + **Falco** + **cert-manager**. Justification à formaliser en ADR dans `docs/adr/`.

---

## 11. Livrables & échéances

**Deux rendus, tous deux à Kick-off + 6 mois :**

1. **Vidéo MVP** (15–20 min, .mp4 ou YouTube non répertorié) : besoin → solution → démo. **Chaque membre parle, nom affiché.**
2. **Document technique final** (zip) : 1 PDF groupe + 1 PDF par membre.
   - PDF groupe : entreprise/équipe, problématique, **gestion des coûts (M2)**, organisation/planif/méthodo, solution technique.
   - PDF individuel : perspectives d'évolution, analyse critique des limites, doc utilisateur, analyse personnelle (défis, forces/faiblesses, compétences, axes d'amélioration).
   - Attendus transverses : code versionné, fichiers d'infra, dashboards (screenshots), **backlog**, **diagramme de Gantt**, justification des choix, contributions individuelles.

**Nomenclature (à compléter avec le code promo) :**
```
PE_2526_<codepromo>_<noms>.zip
PE-2526_<codepromo>_<NomPrenom>.pdf
```
> Kick-off : `<date à renseigner>` — Deadline : `<date à renseigner>`

---

## 12. Consignes pour l'assistant IA

Quand tu interviens sur ce repo :
- **Respecte le stack (§4) et la structure (§6).** Signale toute dérogation.
- **Ne mets jamais de secret en clair** (§8.1). Utilise des placeholders et renvoie vers Vault/SOPS/CI variables.
- **Terraform : montre le `plan`, n'applique pas sans validation.**
- **Cite le rôle concerné** (M1–M4) quand tu produis un livrable, et range le fichier au bon endroit.
- **Documente les choix** : propose un ADR pour toute décision structurante.
- **Code en anglais, doc en français.**
- En cas d'ambiguïté sur une décision ouverte (§10), **demande** plutôt que de trancher seul.
