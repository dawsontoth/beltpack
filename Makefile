REPO := $(shell pwd)
AGENTS := $(HOME)/Library/LaunchAgents

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# ---- build ----------------------------------------------------------------

.PHONY: build
build: server web ## Build everything

.PHONY: server
server: ## Build the WING bridge (release)
	cd server && swift build -c release

.PHONY: web
web: ## Install deps and bundle the PWA
	cd web && npm install && npm run build

.PHONY: ios
ios: ## Regenerate and open the Xcode project
	cd ios && xcodegen generate && open Beltpack.xcodeproj

# ---- run locally ----------------------------------------------------------

.PHONY: devices
devices: ## List Core Audio inputs this Mac can see
	cd server && swift run BeltpackBridge --devices

.PHONY: run-livekit
run-livekit: ## Run the SFU in the foreground
	./deploy/run.sh livekit

.PHONY: run-token
run-token: ## Run the token service in the foreground
	./deploy/run.sh token

.PHONY: run-bridge
run-bridge: server ## Run the WING bridge in the foreground
	./deploy/run.sh bridge

# ---- deploy ---------------------------------------------------------------

.PHONY: install-agents
install-agents: ## Install LaunchAgents pointed at this checkout
	@mkdir -p $(AGENTS) logs
	@for svc in livekit token bridge; do \
		sed 's|REPO|$(REPO)|g' deploy/launchd/org.beltpack.$$svc.plist \
			> $(AGENTS)/org.beltpack.$$svc.plist; \
		echo "installed $(AGENTS)/org.beltpack.$$svc.plist"; \
	done
	@echo
	@echo "Now load them:"
	@echo "  for s in livekit token bridge; do launchctl bootstrap gui/\$$(id -u) $(AGENTS)/org.beltpack.\$$s.plist; done"

.PHONY: uninstall-agents
uninstall-agents: ## Unload and remove the LaunchAgents
	@for svc in livekit token bridge; do \
		launchctl bootout gui/$$(id -u)/org.beltpack.$$svc 2>/dev/null || true; \
		rm -f $(AGENTS)/org.beltpack.$$svc.plist; \
	done
	@echo "removed"

.PHONY: logs
logs: ## Tail all service logs
	tail -f logs/*.log

# ---- checks ---------------------------------------------------------------

.PHONY: check
check: ## Build everything and lint what can be linted
	cd server && swift build
	cd ios && xcodegen generate
	cd web && npm install && npm run build
	node --check token/server.mjs
	bash -n deploy/run.sh
	@for f in deploy/launchd/*.plist; do plutil -lint "$$f"; done
	@echo "all checks passed"

.PHONY: clean
clean: ## Remove build output
	rm -rf server/.build web/dist web/node_modules ios/Beltpack.xcodeproj ios/Info.plist
