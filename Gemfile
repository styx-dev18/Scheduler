source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.4"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
# gem "jbuilder"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 1.2"

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin Ajax possible
gem "rack-cors"
gem "rack-attack", "~> 6.7"
gem "rack-timeout", "~> 0.7"

gem "dry-monads", "~> 1.6"
gem "alba", "~> 3.0"
gem "pagy", "~> 9.0"
gem "strong_migrations", "~> 2.0"
gem "rswag-api", "~> 2.16"
gem "rswag-ui", "~> 2.16"
gem "lograge", "~> 0.14"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  gem "dotenv-rails", "~> 3.1"
  gem "rspec-rails", "~> 8.0"
  gem "factory_bot_rails", "~> 6.4"
  gem "faker", "~> 3.5"
  gem "rswag-specs", "~> 2.16"
  gem "bullet", "~> 8.0"
  gem "lefthook", "~> 1.11", require: false
end

group :test do
  gem "shoulda-matchers", "~> 6.4"
  gem "prop_check", "~> 1.0"
  gem "simplecov", "~> 0.22", require: false
end

gem "yabeda", "~> 0.16.0"
gem "yabeda-rails", "~> 0.11.0"
gem "yabeda-puma-plugin", "~> 0.9.0"
gem "yabeda-prometheus", "~> 0.9.1"

gem "opentelemetry-sdk", "~> 1.6"
gem "opentelemetry-exporter-otlp", "~> 0.29"
gem "opentelemetry-instrumentation-rails", "~> 0.36"
gem "opentelemetry-instrumentation-rack", "~> 0.26"
gem "opentelemetry-instrumentation-pg", "~> 0.30"
gem "opentelemetry-instrumentation-active_record", "~> 0.8"
