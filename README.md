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

## Quick start

No local build required — `kubectl apply` pulls the pre-built image from
`ghcr.io/jonastheiler/shiny-k8s-lab:latest` automatically.

```bash
git clone git@github.com:jonastheiler/shiny-k8s-lab.git
cd shiny-k8s-lab

# Start the cluster
minikube start
minikube addons enable ingress

# Deploy
kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/postgres/
kubectl apply -f k8s/shiny/

# Wait until both pods show 1/1 Running
kubectl get pods -n field-logger -w

# Open the app
kubectl port-forward svc/shiny-service 8080:80 -n field-logger --address=0.0.0.0
```

Open **http://localhost:8080** in your browser.

> **WSL2 on Windows?** See the [WSL2 notes](#wsl2-on-windows) section at the bottom.

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
│   │   ├── 03-deployment.yaml   # PostgreSQL Deployment + init ConfigMap
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

- [Docker](https://docs.docker.com/get-docker/) (Docker Desktop on Mac/Windows, Docker Engine on Linux)
- [minikube](https://minikube.sigs.k8s.io/docs/start/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- A GitHub account (free tier is sufficient — needed only if you want to push your own image via CI)

---

## Step-by-step setup

### Step 1 — Start the Kubernetes cluster

```bash
# Start minikube. It auto-selects the best driver for your OS:
#   macOS   → Docker or HyperKit
#   Linux   → Docker or KVM2
#   Windows (WSL2) → Docker  (see WSL2 notes below)
minikube start

# Enable the nginx Ingress controller addon.
# This installs the ingress-nginx controller into the cluster, which allows
# HTTP routing based on hostname rules defined in Ingress manifests.
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

### Step 2 — Create the project folder structure

```bash
mkdir -p app db k8s/postgres k8s/shiny .github/workflows
```

---

### Step 3 — Write the database schema (`db/init.sql`)

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

### Step 4 — Write the R Shiny app (`app/`)

*(See `app/global.R`, `app/ui.R`, `app/server.R` for the full files with comments.)*

The app has three tabs:
- **Log Entry** — form to submit a new measurement (INSERT)
- **Browse Data** — interactive, filterable table of all entries (SELECT)
- **Stats** — per-measurement-type summary statistics and a ggplot2 boxplot

Key pattern: the database connection uses a **connection pool** (`pool` package) so multiple
concurrent users share connections efficiently without reconnecting on every query.

---

### Step 5 — Write the Dockerfile (`app/Dockerfile`)

*(See `app/Dockerfile` for the full file with comments.)*

Based on `rocker/shiny:latest`. Installs the PostgreSQL client library and all required R packages.

---

### Step 6 — Write the Kubernetes manifests (`k8s/`)

*(See each file in `k8s/` for the full manifests with comments.)*

Applied in dependency order:

1. `00-namespace.yaml` — workspace isolation
2. `01-secret.yaml` — encrypted DB credentials
3. `02-pvc.yaml` — persistent disk for the database
4. `03-deployment.yaml` — PostgreSQL container + init ConfigMap
5. `04-service.yaml` — internal DNS for the DB
6. `05-configmap.yaml` — non-sensitive Shiny app config
7. `06-deployment.yaml` — Shiny container
8. `07-service.yaml` — internal DNS for Shiny
9. `08-ingress.yaml` — external HTTP access

---

### Step 7 — Deploy to the cluster

```bash
# Apply all manifests in order (or use: make deploy)
kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/postgres/
kubectl apply -f k8s/shiny/

# Watch Pods come up — wait until both show 1/1 Running (Ctrl+C to exit)
kubectl get pods -n field-logger -w
```

Expected output once ready:
```
NAME                         READY   STATUS    RESTARTS   AGE
postgres-xxx                 1/1     Running   0          60s
shiny-app-xxx                1/1     Running   0          60s
```

---

### Step 8 — Access the app

```bash
# Forward the Shiny service to port 8080 (keep this terminal open)
kubectl port-forward svc/shiny-service 8080:80 -n field-logger --address=0.0.0.0
```

Open **http://localhost:8080** in your browser.

To access the database directly (e.g. from DBeaver or psql):

```bash
# Decode credentials from the Secret
kubectl get secret postgres-secret -n field-logger \
  -o jsonpath='{.data.POSTGRES_USER}' | base64 -d

kubectl get secret postgres-secret -n field-logger \
  -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d

# Forward the PostgreSQL port
kubectl port-forward svc/postgres-service 5432:5432 -n field-logger --address=0.0.0.0
# Connect to localhost:5432 with the credentials above
```

---

### Step 9 — GitHub Actions CI

*(See `.github/workflows/build-and-push.yml` for the full workflow with comments.)*

On every push to `main` that touches `app/`, GitHub Actions:
1. Checks out the code
2. Logs into GitHub Container Registry (`ghcr.io`) using the built-in `GITHUB_TOKEN`
3. Builds the Shiny Docker image
4. Pushes it tagged with both `latest` and the commit SHA

After a new image is pushed, force the cluster to pull it:

```bash
kubectl rollout restart deployment/shiny-app -n field-logger
# or: make restart
```

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

## Lessons learned

- **Docker driver for minikube**: On some systems the default driver requires a hypervisor. If `minikube start` fails, try `minikube start --driver=docker` to use Docker as the node runtime instead.

- **Ingress addon**: Must be enabled before applying the Ingress manifest, or the Ingress will have no address.

- **imagePullPolicy: Always**: The Shiny Deployment uses this so that `kubectl rollout restart` always pulls the latest image from ghcr.io without needing a tag change.

- **s6-overlay and Renviron.site**: The `rocker/shiny` image uses `s6-overlay` as PID 1. Its `01_set_env` init script writes Kubernetes environment variables (DB_HOST, DB_PORT, etc.) into `/usr/local/lib/R/etc/Renviron.site` so R can read them via `Sys.getenv()`. Without `chmod 666` on that file the script silently skips the variables and `dbPool()` tries to connect via Unix socket instead of TCP.

- **Connection pool over a single connection**: `dbPool()` keeps several database connections open and hands them out on demand. A single `dbConnect()` would serialize all queries — the second user has to wait for the first. The pool eliminates that bottleneck.

---

## WSL2 on Windows

Running minikube on WSL2 with the Docker driver requires a few extra steps.

**Use the Docker driver explicitly:**
```bash
minikube start --driver=docker
```

**Fix broken DNS (if `curl` cannot resolve hostnames):**
```bash
# Override with Google's public DNS
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf

# To make this permanent across WSL restarts:
sudo tee /etc/wsl.conf > /dev/null <<EOF
[network]
generateResolvConf = false
EOF

sudo tee /etc/resolv.conf > /dev/null <<EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF
```

Restart WSL from PowerShell after changing `/etc/wsl.conf`:
```powershell
wsl --shutdown
```

**Browser access via port-forward:**
`minikube tunnel` binds to `127.0.0.1` inside WSL2, which Windows cannot reach directly.
`kubectl port-forward --address=0.0.0.0` binds on all interfaces, which WSL2 forwards to
Windows automatically. This is why the Quick Start uses port-forward instead of the Ingress
hostname — it works on all platforms without any hosts file configuration.

**Avoid `.local` hostnames in Chrome:**
`.local` is reserved for mDNS (Bonjour/Avahi). Chrome may route `.local` hostnames through
mDNS rather than `/etc/hosts`, making the address unreachable. Accessing the app via
`localhost:PORT` sidesteps this entirely.

---

## Author

Jonas Theiler — senior data scientist learning cloud-native deployment patterns.
