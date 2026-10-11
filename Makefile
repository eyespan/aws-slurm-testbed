# HPC Platform Operations Test Bed - Makefile
# Common targets for development and deployment

.PHONY: help preflight up down plan apply drift test lint evidence clean validate

help:
	@echo "HPC Platform Operations Test Bed"
	@echo ""
	@echo "Targets:"
	@echo "  preflight   - Verify identity, region, and remaining capacity"
	@echo "  up          - Apply infrastructure with evidence export"
	@echo "  down        - Destroy infrastructure with evidence export"
	@echo "  plan        - Generate terraform plan"
	@echo "  apply       - Apply terraform changes"
	@echo "  drift       - Check for configuration drift"
	@echo "  test        - Run pytest tests"
	@echo "  lint        - Run static analysis"
	@echo "  evidence    - Generate evidence pack"
	@echo "  fsx-up      - Deploy FSx for Lustre scratch storage"
	@echo "  fsx-down    - Destroy FSx for Lustre scratch storage"
	@echo "  controller  - Validate and apply controller module"
	@echo "  controller-apply - Apply controller module"
	@echo "  controller-plan - Plan controller module"

# =============================================================================
# Quality Gates
# =============================================================================

preflight:
	@echo "Running preflight checks..."
	python3 scripts/preflight.py

test:
	@echo "Running pytest tests..."
	python3 -m pytest tests/ -v --tb=short

lint:
	@echo "Running static analysis..."
	python3 -m ruff check scripts/ tests/ || true
	python3 -m black --check scripts/ tests/ || true

# =============================================================================
# Terraform Targets
# =============================================================================

plan:
	@echo "Generating terraform plan..."
	cd terraform/bootstrap && terraform plan -out=tfplan -no-color || true

apply:
	@echo "Applying terraform changes..."
	cd terraform/bootstrap && terraform apply -auto-approve tfplan || true

drift:
	@echo "Checking for configuration drift..."
	cd terraform/bootstrap && terraform plan -detailed-exitcode || true

# =============================================================================
# Bootstrap Module Targets
# =============================================================================

bootstrap:
	@echo "Validating and applying bootstrap security module..."
	cd terraform/bootstrap && terraform init -input=false && terraform validate && terraform apply -auto-approve || true

# =============================================================================
# Deployment Targets
# =============================================================================

up:
	@echo "Starting deployment..."
	python3 scripts/deploy.py up

down:
	@echo "Starting destruction..."
	python3 scripts/deploy.py down

# =============================================================================
# Evidence Generation
# =============================================================================

evidence:
	@echo "Generating evidence pack..."
	@mkdir -p evidence
	python3 scripts/evidence.py || echo "Evidence generation not yet implemented."

# =============================================================================
# Helper Targets
# =============================================================================

clean:
	@echo "Cleaning up..."
	rm -rf .terraform terraform.tfstate terraform.tfstate.backup
	rm -rf .terraform.lock.hcl
	rm -rf terraform.tfplan tfplan.json

validate:
	@echo "Validating terraform configuration..."
	cd terraform/bootstrap && terraform validate || true

# =============================================================================
# FSx for Lustre Targets
# =============================================================================

fsx-up:
	@echo "Deploying FSx for Lustre scratch storage..."
	cd terraform && terraform init -input=false && terraform apply -target=module.fsx -auto-approve -var="enable_fsx=true" || true

fsx-down:
	@echo "Destroying FSx for Lustre scratch storage..."
	cd terraform && terraform destroy -target=module.fsx -auto-approve -var="enable_fsx=true" || true

# =============================================================================
# Controller Module Targets
# =============================================================================

controller:
	@echo "Validating and applying controller module..."
	cd terraform/controller && terraform init -input=false && terraform validate && terraform apply -auto-approve || true

controller-apply:
	@echo "Applying controller module..."
	cd terraform/controller && terraform apply -auto-approve || true

controller-plan:
	@echo "Planning controller module..."
	cd terraform/controller && terraform plan -out=tfplan -no-color || true

