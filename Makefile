.PHONY: materialize privacy-test capture-test test server-init server-up server-down backup

materialize:
	bash scripts/materialize-upstream.sh

privacy-test:
	bash scripts/privacy-audit.sh

capture-test:
	gradle -p prototype/android-capture test --no-daemon

test: privacy-test capture-test

server-init:
	bash scripts/server-init.sh

server-up:
	cd deploy && docker compose --env-file .env up -d

server-down:
	cd deploy && docker compose --env-file .env down

backup:
	bash scripts/backup.sh
