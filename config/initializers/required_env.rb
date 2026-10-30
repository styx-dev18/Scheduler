if Rails.env.production?
  ENV.fetch("DATABASE_URL") { ENV.fetch("DB_HOST") { abort "Missing required environment variable: DATABASE_URL or DB_HOST" } }
  ENV.fetch("CORS_ORIGINS") { abort "Missing required environment variable: CORS_ORIGINS" }
end
