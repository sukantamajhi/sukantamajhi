# Generate GitHub profile summary cards locally and push them.
# Usage: make help

SHELL       := /bin/bash
WORKFLOW    := .github/workflows/profile-summary-cards.yml
OUTPUT_DIR  := profile-summary-card-output
THEME       := tokyonight
ACT_IMAGE   ?= catthehacker/ubuntu:act-latest
COMMIT_MSG  ?= Update profile summary cards
CARDS       := 0-profile-details 1-repos-per-language 2-most-commit-language 3-stats 4-productive-time

.DEFAULT_GOAL := help
.PHONY: help check cards fix-perms verify commit push update clean

help: ## Show available commands
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

check: ## Check tools, Docker and gh token scopes
	@for cmd in git gh act docker; do \
	    command -v $$cmd >/dev/null || { echo "Missing: $$cmd"; exit 1; }; \
	done
	@docker info >/dev/null 2>&1 || { echo "Docker is not running. Start it and retry."; exit 1; }
	@gh auth status 2>&1 | grep -q "read:user" || { \
	    echo "Your gh token is missing the read:user scope. Run:"; \
	    echo "  gh auth refresh -h github.com -s read:user"; exit 1; }
	@echo "All checks passed."

cards: check ## Generate the cards with act (writes into this folder)
	@echo "Running workflow with act..."
	@# The Action's own commit step fails inside act's container; we commit ourselves.
	-act workflow_dispatch --bind -W $(WORKFLOW) \
	    -P ubuntu-latest=$(ACT_IMAGE) \
	    -s GITHUB_TOKEN="$$(gh auth token)"
	@$(MAKE) --no-print-directory fix-perms verify

fix-perms: ## Take ownership of files Docker created as root
	@if [ -d $(OUTPUT_DIR) ] && [ -n "$$(find $(OUTPUT_DIR) ! -user $$(id -u) -print -quit)" ]; then \
	    echo "Fixing ownership of $(OUTPUT_DIR) (may ask for your password)..."; \
	    sudo chown -R "$$(id -u):$$(id -g)" $(OUTPUT_DIR); \
	fi

verify: ## Confirm every card the README uses exists
	@missing=0; for c in $(CARDS); do \
	    f="$(OUTPUT_DIR)/$(THEME)/$$c.svg"; \
	    if [ -f "$$f" ]; then echo "  ok      $$f"; else echo "  MISSING $$f"; missing=1; fi; \
	done; \
	if [ $$missing -ne 0 ]; then \
	    echo "Some cards are missing. Generated files:"; ls -R $(OUTPUT_DIR) 2>/dev/null || echo "  (no output folder)"; exit 1; \
	fi

commit: ## Commit the generated cards (skips if nothing changed)
	@git add $(OUTPUT_DIR)
	@if git diff --cached --quiet -- $(OUTPUT_DIR); then \
	    echo "No card changes to commit."; \
	else \
	    git commit -m "$(COMMIT_MSG)" -- $(OUTPUT_DIR); \
	fi

push: ## Push to GitHub
	git push

update: cards commit push ## Generate, commit and push in one go

clean: ## Delete generated cards
	@[ -d $(OUTPUT_DIR) ] && { rm -rf $(OUTPUT_DIR) 2>/dev/null || sudo rm -rf $(OUTPUT_DIR); } || true
	@echo "Removed $(OUTPUT_DIR)."
