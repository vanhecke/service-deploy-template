SHELL := /bin/bash
.DEFAULT_GOAL := help

SCRIPTS := $(shell find lib bin -type f -name '*.sh' 2>/dev/null)

##@ Development
.PHONY: lint
lint: ## Run ShellCheck on all scripts
	shellcheck -x $(SCRIPTS)

.PHONY: format
format: ## Format scripts with shfmt
	shfmt -w -i 4 -ci .

.PHONY: format-check
format-check: ## Check formatting without modifying
	shfmt -d -i 4 -ci .

.PHONY: test
test: ## Run bats-core tests
	bats --print-output-on-failure tests/

.PHONY: check
check: lint format-check test ## Run all checks (CI target)

##@ Helpers
.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS=":.*##";printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} \
	/^[a-zA-Z_-]+:.*?##/{printf "  \033[36m%-15s\033[0m %s\n",$$1,$$2} \
	/^##@/{printf "\n\033[1m%s\033[0m\n",substr($$0,5)}' $(MAKEFILE_LIST)
