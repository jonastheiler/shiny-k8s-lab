# shiny-k8s-lab

> **A senior data scientist's guide to deploying a full-stack data application on Kubernetes.**
>
> This project walks through every step of containerising an R Shiny CRUD app backed by PostgreSQL
> and deploying it on a local Kubernetes cluster (minikube). The goal is to demonstrate cloud-native
> deployment skills that go beyond Docker Compose — covering Deployments, Services, PersistentVolumes,
> Secrets, ConfigMaps, Ingress, and a GitHub Actions CI pipeline.

---

## What this project builds

A **Field Measurement Logger** — a web app where researchers log environmental measurements
(location, type, value, unit, observer, notes). Built with:

| Component | Technology | Why |
|---|---|---|
| Frontend / App | R Shiny | Interactive data apps in pure R |
| Database | PostgreSQL 15 | Reliable, open-source relational DB |
| Containerisation | Docker | Reproducible, portable environments |
| Orchestration | Kubernetes (minikube) | Production-grade container management |
| CI Pipeline | GitHub Actions | Automated image build and push on every commit |
| Image Registry | GitHub Container Registry (ghcr.io) | Free, integrated with GitHub Actions |

---

## Repository structure

```
.
├── .github/
│   └── workflows/
│       └── build-and-push.yml   # CI: builds and pushes the Shiny Docker image
├── app/
│   ├── Dockerfile               # Shiny app container definition
│   ├── global.R                 # Database connection pool, shared config
│   ├── ui.R                     # Shiny user interface
│   └── server.R                 # Shiny server logic (CRUD operations)
├── db/
│   └── init.sql                 # PostgreSQL schema definition
├── k8s/
│   ├── 00-namespace.yaml        # Kubernetes Namespace (isolated workspace)
│   ├── postgres/
│   │   ├── 01-secret.yaml       # DB credentials (never hardcoded)
│   │   ├── 02-pvc.yaml          # Persistent storage for DB data
│   │   ├── 03-deployment.yaml   # PostgreSQL Deployment
│   │   └── 04-service.yaml      # Internal DNS name for the DB
│   └── shiny/
│       ├── 05-configmap.yaml    # Non-sensitive app configuration
│       ├── 06-deployment.yaml   # Shiny app Deployment
│       ├── 07-service.yaml      # Internal DNS name for the Shiny app
│       └── 08-ingress.yaml      # External HTTP access via hostname
├── Makefile                     # Convenience commands (deploy, teardown, logs)
└── README.md                    # You are here
```

---

## Prerequisites

- Windows 10/11 with WSL2 enabled
- Ubuntu 22.04 WSL2 distro
- Docker Desktop with WSL2 integration enabled for Ubuntu-22.04
- A GitHub account (free tier is sufficient)

---

## Step-by-step setup

### Step 1 — Fix WSL2 DNS (if needed)

WSL2 sometimes generates a broken `/etc/resolv.conf`. If `curl` cannot resolve hostnames,
override the nameserver:

```bash
# Check what DNS server WSL2 is currently using
cat /etc/resolv.conf

# Override with Google's public DNS (8.8.8.8)
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
```

To make this fix permanent across WSL restarts:

```bash
# 1. Prevent WSL from overwriting resolv.conf on startup
sudo tee /etc/wsl.conf > /dev/null <<EOF
[network]
generateResolvConf = false
EOF

# 2. Write a permanent resolv.conf
sudo tee /etc/resolv.conf > /dev/null <<EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF
```

After changing `/etc/wsl.conf`, restart WSL from PowerShell:
```powershell
wsl --shutdown
# Then reopen your Ubuntu terminal
```

---

### Step 2 — Install minikube

minikube runs a single-node Kubernetes cluster as a Docker container inside WSL2.

```bash
# Download the minikube binary for Linux (amd64)
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64

# Install it to /usr/local/bin so it is available system-wide
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# Remove the downloaded file — we only needed it for the install
rm minikube-linux-amd64

# Verify the installation
minikube version
```

---

### Step 3 — Install kubectl

`kubectl` is the Kubernetes command-line tool — the primary way to interact with the cluster.

```bash
# Fetch the latest stable release version number, then download that binary
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

# Install system-wide
sudo install kubectl /usr/local/bin/kubectl

# Clean up
rm kubectl

# Verify
kubectl version --client
```

---

### Step 4 — Start the Kubernetes cluster

```bash
# Start minikube using Docker as the driver.
# The Docker driver creates a container that acts as the Kubernetes node —
# no VM or hypervisor needed since Docker Desktop is already running.
minikube start --driver=docker

# Enable the nginx Ingress controller addon.
# This is what allows us to expose the Shiny app via a hostname (field-logger.local)
# rather than an IP address and port number.
minikube addons enable ingress

# Verify the cluster is running — you should see one node with status Ready
kubectl get nodes
```

Expected output:
```
NAME       STATUS   ROLES           AGE   VERSION
minikube   Ready    control-plane   1m    v1.x.x
```

---

### Step 5 — Create the project folder structure

```bash
mkdir -p app db k8s/postgres k8s/shiny .github/workflows
```

---

### Step 6 — Write the database schema (`db/init.sql`)

*(See `db/init.sql` for the full file with comments.)*

The schema defines one table: `measurements`. Every field is chosen for a real field-data
collection workflow:

| Column | Type | Purpose |
|---|---|---|
| `id` | SERIAL PRIMARY KEY | Auto-incrementing unique identifier |
| `observed_at` | TIMESTAMPTZ | Timestamp with timezone — critical for field data |
| `location` | TEXT | Site name or GPS description |
| `measurement_type` | TEXT | What was measured (pH, temperature, etc.) |
| `value` | NUMERIC | The numeric reading |
| `unit` | TEXT | Unit of measure (°C, mg/L, NTU, etc.) |
| `observer` | TEXT | Who collected the data |
| `notes` | TEXT | Free-text remarks |

---

### Step 7 — Write the R Shiny app (`app/`)

*(See `app/global.R`, `app/ui.R`, `app/server.R` for the full files with comments.)*

The app has three tabs:
- **Log Entry** — form to submit a new measurement (INSERT)
- **Browse Data** — interactive, filterable table of all entries (SELECT)
- **Stats** — per-measurement-type summary statistics and a ggplot2 boxplot

Key pattern: the database connection uses a **connection pool** (`pool` package) so multiple
concurrent users share connections efficiently without reconnecting on every query.

---

### Step 8 — Write the Dockerfile (`app/Dockerfile`)

*(See `app/Dockerfile` for the full file with comments.)*

Based on `rocker/shiny:latest`. Installs the PostgreSQL client library and all required R packages.

---

### Step 9 — Write the Kubernetes manifests (`k8s/`)

*(See each file in `k8s/` for the full manifests with comments.)*

Applied in dependency order:

1. `00-namespace.yaml` — workspace isolation
2. `01-secret.yaml` — encrypted DB credentials
3. `02-pvc.yaml` — persistent disk for the database
4. `03-deployment.yaml` — PostgreSQL container
5. `04-service.yaml` — internal DNS for the DB
6. `05-configmap.yaml` — non-sensitive Shiny app config
7. `06-deployment.yaml` — Shiny container
8. `07-service.yaml` — internal DNS for Shiny
9. `08-ingress.yaml` — external HTTP access

---

### Step 10 — Deploy to the cluster

```bash
# Apply all manifests in order
kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/postgres/
kubectl apply -f k8s/shiny/

# Watch Pods come up (Ctrl+C to exit)
kubectl get pods -n field-logger -w

# Get the app URL
kubectl get ingress -n field-logger
```

Add the minikube IP to your hosts file so the hostname resolves:
```bash
echo "$(minikube ip) field-logger.local" | sudo tee -a /etc/hosts
```

Open `http://field-logger.local` in your browser.

---

### Step 11 — GitHub Actions CI

*(See `.github/workflows/build-and-push.yml` for the full workflow with comments.)*

On every push to `main` that touches `app/`, GitHub Actions:
1. Checks out the code
2. Logs into GitHub Container Registry (`ghcr.io`) using the built-in `GITHUB_TOKEN`
3. Builds the Shiny Docker image
4. Pushes it tagged with both `latest` and the commit SHA

---

## Key Kubernetes concepts used

| Concept | What it does in this project |
|---|---|
| **Namespace** | Groups all resources for this app; prevents conflicts with other workloads |
| **Secret** | Stores the PostgreSQL password; mounted as env vars — never in source code |
| **ConfigMap** | Stores the DB hostname and port; can change without rebuilding the image |
| **PersistentVolumeClaim** | Requests durable storage; PostgreSQL data survives Pod restarts |
| **Deployment** | Declares desired state; restarts Pods automatically if they crash |
| **Service (ClusterIP)** | Gives the DB and Shiny app stable internal DNS names within the cluster |
| **Ingress** | Routes external HTTP requests to the Shiny service by hostname |

---

## Lessons learned / pitfalls

- **WSL2 DNS**: WSL2 may generate a broken `resolv.conf`. Always verify `curl` works before proceeding.
- **Docker driver for minikube**: Must use `--driver=docker` on WSL2 — the default VM drivers require a hypervisor that conflicts with WSL2's own VM layer.
- **Ingress addon**: Must be enabled before applying the Ingress manifest, or the Ingress will have no address.
- **Hosts file**: minikube does not auto-register hostnames — you must manually add `$(minikube ip) field-logger.local` to `/etc/hosts`.

---

## Author

Jonas Theiler — senior data scientist learning cloud-native deployment patterns.
