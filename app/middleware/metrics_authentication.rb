class MetricsAuthentication
  DETAIL = "Invalid or missing metrics token".freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    return @app.call(env) if authorized?(env)

    unauthorized_response
  end

  private

  def authorized?(env)
    token = ENV["METRICS_TOKEN"].presence
    return true if token.nil?

    supplied = env["HTTP_AUTHORIZATION"].to_s.delete_prefix("Bearer ")
    ActiveSupport::SecurityUtils.secure_compare(supplied, token)
  end

  def unauthorized_response
    entry = ErrorCatalogue.fetch("UNAUTHORIZED")
    [ entry.status, { "content-type" => "application/json", "www-authenticate" => "Bearer" }, [ body(entry).to_json ] ]
  end

  def body(entry)
    {
      success: false, data: nil,
      error: { type: "https://httpstatuses.com/#{entry.status}", title: entry.title, status: entry.status,
               code: entry.code, detail: DETAIL },
      message: DETAIL
    }
  end
end
