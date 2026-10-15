# HPC Platform Operations Test Bed - Makefile
# Common targets for development and deployment

.PHONY: help preflight up down foundation instances plan apply drift test lint evidence clean validate ami-build

help:
	@echo "HPC Platform Operations Test Bed"
	@echo ""
	@echo "REQUIRED deploy order (AMI before instances):"
	@echo "  1) make foundation   # VPC, subnets, SGs, EFS, Image Builder pipeline"
	@echo "  2) make ami-build    # run pipeline, wait, promote AMI to SSM"
	@echo "  3) make instances    # controller + login + debug EC2"
	@echo ""
	@echo "  Or all-in-one:  make up   # runs 1 → 2 → 3"
	@echo "  Skip AMI step:  python3 scripts/deploy.py up --skip-ami"
	@echo ""
	@echo "Targets:"
	@echo "  foundation  - Phase 1: bootstrap + network + storage + image_builder"
	@echo "  ami-build   - Phase 2: start Image Builder, wait, promote to SSM"
	@echo "  instances   - Phase 3: controller + login + debug (needs AMI)"
	@echo "  up          - Ordered full deploy (foundation → ami-build → instances)"
	@echo "  down        - Destroy infrastructure with evidence export"
	@echo "  preflight   - Verify identity, region, and remaining capacity"
	@echo "  plan        - Generate terraform plan"
	@echo "  apply       - Apply terraform changes (CONFIRM=yes)"
	@echo "  drift       - Check for configuration drift"
	@echo "  test        - Run pytest tests"
	@echo "  lint        - Run static analysis"
	@echo "  evidence    - Generate evidence pack"
	@echo "  fsx-up      - Deploy FSx for Lustre scratch storage"
	@echo "  fsx-down    - Destroy FSx for Lustre scratch storage"

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
	@mkdir -p evidence
	cd terraform && terraform init -input=false
	cd terraform && terraform plan -out=../evidence/tfplan-$$(date -u +%Y%m%dT%H%M%SZ) -no-color

apply:
	@echo "Applying terraform changes (requires CONFIRM=yes)..."
	@if [ "$$CONFIRM" != "yes" ]; then echo "Refusing apply without CONFIRM=yes"; exit 1; fi
	@mkdir -p evidence
	cd terraform && terraform apply -auto-approve

drift:
	@echo "Checking for configuration drift..."
	@mkdir -p evidence
	cd terraform && terraform plan -detailed-exitcode -no-color | tee evidence/drift-$$(date -u +%Y%m%dT%H%M%SZ).txt; 		ec=$$?; if [ $$ec -eq 2 ]; then echo "DRIFT DETECTED"; exit 2; fi; exit $$ec

# =============================================================================
# Bootstrap Module Targets
# =============================================================================

bootstrap:
	@echo "Validating and applying bootstrap security module..."
	cd terraform/bootstrap && terraform init -input=false && terraform validate && terraform apply -auto-approve || true

# =============================================================================
# Deployment Targets (phased: foundation → AMI → instances)
# =============================================================================

foundation:
	@echo "Phase 1: foundation (VPC/subnets/SGs/EFS + Image Builder pipeline)..."
	python3 scripts/deploy.py foundation

instances:
	@echo "Phase 3: instances (controller + login + debug)..."
	python3 scripts/deploy.py instances

up:
	@echo "Ordered deploy: foundation → ami-build → instances..."
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
# Controller is a *child* module under terraform/. Running terraform apply inside
# terraform/controller treats it as a root module (missing wiring from network/
# bootstrap/storage) and can produce confusing "undeclared variable" errors.
# Always apply from the root stack.

controller controller-apply controller-plan:
	@echo "ERROR: controller is not a standalone root module."
	@echo "Use the full stack instead:"
	@echo "  make plan"
	@echo "  make apply"
	@echo "  # or:  python3 scripts/deploy.py up"
	@echo "  # targeted:  cd terraform && terraform apply -target=module.controller"
	@exit 1


# =============================================================================
# AMI lifecycle (Task 24)
# =============================================================================

ami-build:
	@echo "Phase 2: start Image Builder pipeline, wait for AMI, promote to SSM current"
	@echo "(Requires foundation first so the pipeline ARN exists)"
	@echo "(Pipeline does NOT run on terraform apply — only weekly cron or this target)"
	python3 scripts/ami_build.py

ami-promote:
	@echo "Promote candidate AMI (usage: make ami-promote AMI=ami-xxx)"
	python3 scripts/image_promote.py promote --ami $(AMI)

ami-rollback:
	@echo "Rolling back compute AMI current <-> previous"
	python3 scripts/image_promote.py rollback

# =============================================================================
# Service report (Task 35)
# =============================================================================

service-report:
	@echo "Generating service report..."
	python3 scripts/service_report.py --output docs/service-reports/report-$$(date -u +%Y%m).json || true
