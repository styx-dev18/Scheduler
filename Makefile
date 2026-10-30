.PHONY: setup up test lint reset-db docs

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
