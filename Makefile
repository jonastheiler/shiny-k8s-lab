# =============================================================================
# File:    Makefile
# Purpose: Convenience commands for managing the shiny-k8s-lab deployment.
#
# What is a Makefile?
#   A Makefile defines named targets (like "deploy", "teardown") that group
#   multiple shell commands under one short command: make <target>.
#   It is the standard way to document and automate operational tasks in a
#   project — a lightweight alternative to bash scripts.
#
# Usage:
#   make deploy      — apply all Kubernetes manifests in dependency order
#   make teardown    — delete all resources (data is lost — PVC is deleted too)
#   make status      — show the current state of all resources in the namespace
#   make logs-shiny  — tail logs from the Shiny app Pod
#   make logs-pg     — tail logs from the PostgreSQL Pod
#   make restart     — force a rolling restart of the Shiny Deployment
#   make url         — print the URL to open in the browser
#
# Requirements:
#   kubectl and minikube must be installed and the cluster must be running.
# =============================================================================

# The Kubernetes namespace used by this project.
# Defined once here so changing it propagates to all targets automatically.
NAMESPACE := field-logger

# Default target: running `make` with no arguments prints available commands.
.DEFAULT_GOAL := help

# .PHONY tells Make that these targets are not files — they are always executed,
# even if a file with the same name exists in the directory.
.PHONY: help deploy teardown status logs-shiny logs-pg restart url

# -----------------------------------------------------------------------------
# help — list all available targets with descriptions
# -----------------------------------------------------------------------------
help:
	@echo ""
	@echo "shiny-k8s-lab — available commands:"
	@echo ""
	@echo "  make deploy      Apply all Kubernetes manifests (creates/updates resources)"
	@echo "  make teardown    Delete all resources including persistent storage"
	@echo "  make status      Show Pods, Services, and Ingress in the namespace"
	@echo "  make logs-shiny  Tail logs from the Shiny app container"
	@echo "  make logs-pg     Tail logs from the PostgreSQL container"
	@echo "  make restart     Force a rolling restart of the Shiny Deployment"
	@echo "  make url         Print the URL to open in the browser"
	@echo ""

# -----------------------------------------------------------------------------
# deploy — apply all manifests in dependency order
# The numbered filenames (00-, 01-, ...) ensure correct ordering when applying
# the postgres/ and shiny/ directories — namespace before secrets before Pods.
# -----------------------------------------------------------------------------
deploy:
	@echo ">>> Creating namespace..."
	kubectl apply -f k8s/00-namespace.yaml

	@echo ">>> Deploying PostgreSQL..."
	kubectl apply -f k8s/postgres/

	@echo ">>> Deploying Shiny app..."
	kubectl apply -f k8s/shiny/

	@echo ""
	@echo ">>> Waiting for Pods to be ready (this may take ~60 seconds)..."
	kubectl wait --for=condition=ready pod -l app=postgres  -n $(NAMESPACE) --timeout=120s
	kubectl wait --for=condition=ready pod -l app=shiny-app -n $(NAMESPACE) --timeout=120s

	@echo ""
	@echo ">>> Done. Run 'make url' to get the app address."

# -----------------------------------------------------------------------------
# teardown — delete everything including the PVC (all data will be lost)
# This is useful for a clean reset during development.
# -----------------------------------------------------------------------------
teardown:
	@echo ">>> WARNING: This will delete all resources AND persistent data."
	@echo ">>> Press Ctrl+C within 5 seconds to cancel..."
	@sleep 5
	kubectl delete namespace $(NAMESPACE) --ignore-not-found
	@echo ">>> Namespace $(NAMESPACE) deleted."

# -----------------------------------------------------------------------------
# status — overview of all running resources in the namespace
# -----------------------------------------------------------------------------
status:
	@echo "=== Pods ==="
	kubectl get pods -n $(NAMESPACE) -o wide

	@echo ""
	@echo "=== Services ==="
	kubectl get services -n $(NAMESPACE)

	@echo ""
	@echo "=== Ingress ==="
	kubectl get ingress -n $(NAMESPACE)

	@echo ""
	@echo "=== PersistentVolumeClaims ==="
	kubectl get pvc -n $(NAMESPACE)

# -----------------------------------------------------------------------------
# logs-shiny — stream logs from the Shiny app Pod
# The -l flag selects the Pod by label rather than by name, so this works
# even after the Pod has been replaced with a new one.
# -----------------------------------------------------------------------------
logs-shiny:
	kubectl logs -n $(NAMESPACE) -l app=shiny-app --follow --tail=100

# -----------------------------------------------------------------------------
# logs-pg — stream logs from the PostgreSQL Pod
# -----------------------------------------------------------------------------
logs-pg:
	kubectl logs -n $(NAMESPACE) -l app=postgres --follow --tail=100

# -----------------------------------------------------------------------------
# restart — force a rolling restart of the Shiny Deployment
# Useful after pushing a new image to ghcr.io with imagePullPolicy: Always —
# the restart forces Kubernetes to pull the latest image without changing YAML.
# -----------------------------------------------------------------------------
restart:
	kubectl rollout restart deployment/shiny-app -n $(NAMESPACE)
	@echo ">>> Restart triggered. Watch progress with: make status"

# -----------------------------------------------------------------------------
# url — print the port-forward command to access the app in a browser
# -----------------------------------------------------------------------------
url:
	@echo ""
	@echo "=== Access the app ==="
	@echo ""
	@echo "Run this command (keep the terminal open):"
	@echo "  kubectl port-forward svc/shiny-service 8080:80 -n $(NAMESPACE) --address=0.0.0.0"
	@echo ""
	@echo "Then open: http://localhost:8080"
	@echo ""
