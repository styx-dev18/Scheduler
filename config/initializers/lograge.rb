Rails.application.configure do
  config.lograge.enabled = Rails.env.production? || ENV["LOGRAGE_ENABLED"] == "true"
  config.lograge.formatter = Lograge::Formatters::Json.new
  config.lograge.ignore_actions = []
  config.lograge.custom_options = lambda do |event|
    {
      request_id: Current.request_id || event.payload[:request_id],
      trace_id: Current.trace_id,
      appointment_id: Current.appointment_id || event.payload[:params]&.dig("id"),
      method: event.payload[:method],
      path: event.payload[:path],
      status: event.payload[:status],
      duration: event.duration.round(2)
    }.compact
  end
end
