class Rack::Attack
  SAFELISTED_PATHS = %r{\A/(up|health(/.*)?|metrics)\z}

  def self.enabled_for_environment?
    ENV.fetch("RATE_LIMIT_ENABLED", Rails.env.test? ? "false" : "true") == "true"
  end

  def self.limit(name)
    Integer(ENV.fetch(name == "BOOKING" ? "RATE_LIMIT_BOOKING_REQUESTS" : "RATE_LIMIT_REQUESTS", name == "BOOKING" ? "20" : "300"))
  end

  def self.period(name)
    Integer(ENV.fetch(name == "BOOKING" ? "RATE_LIMIT_BOOKING_PERIOD" : "RATE_LIMIT_PERIOD", "60")).seconds
  end

  self.enabled = enabled_for_environment?

  safelist("health and metrics") { |request| request.path.match?(SAFELISTED_PATHS) }

  throttle("booking/ip", limit: ->(_request) { limit("BOOKING") }, period: period("BOOKING")) do |request|
    request.ip if request.post? && request.path == "/api/v1/appointments"
  end

  throttle("general/ip", limit: ->(_request) { limit("GENERAL") }, period: period("GENERAL")) do |request|
    request.ip
  end

  self.throttled_responder = lambda do |request|
    match = request.env["rack.attack.match_data"] || {}
    period = match[:period].to_i
    retry_after = period.positive? ? period - (match[:epoch_time].to_i % period) : 1
    entry = ErrorCatalogue.fetch("RATE_LIMITED")
    detail = "Rate limit exceeded. Retry after #{retry_after} seconds"
    error = {
      type: "https://httpstatuses.com/#{entry.status}",
      title: entry.title,
      status: entry.status,
      code: entry.code,
      detail: detail
    }
    body = { success: false, data: nil, error: error, message: detail }.to_json
    [ entry.status, { "Content-Type" => "application/json", "Retry-After" => retry_after.to_s }, [ body ] ]
  end
end
