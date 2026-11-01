.PHONY: setup up test lint reset-db docs api-check

POSTMAN ?= postman
BASE_URL ?=

setup:
	bin/setup

up:
	bin/dev

test:
	bundle exec rspec

lint:
	bundle exec rubocop

reset-db:
	bin/rails db:drop db:create db:migrate

docs:
	bundle exec rake rswag:specs:swaggerize

api-check:
	$(POSTMAN) collection run "postman/collections/Unified Service Scheduler" -e postman/environments/local.environment.yaml $(if $(BASE_URL),--env-var baseUrl=$(BASE_URL))
