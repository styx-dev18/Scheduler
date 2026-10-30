ActiveSupport::Notifications.subscribe(/\Aappointment\./) do |event|
  Rails.logger.info({ event: event.name, **event.payload }.to_json)
end
