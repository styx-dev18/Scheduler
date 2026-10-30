module Envelope
  extend ActiveSupport::Concern

  private

  def render_success(data, status: :ok, message: nil, meta: nil)
    body = { success: true, data: data, error: nil, message: message }
    body[:meta] = meta if meta
    render json: body, status: status
  end

  def render_failure(code, detail: nil, errors: nil, status: nil, extra: nil)
    entry = ErrorCatalogue.fetch(code)
    if entry.nil?
      raise ArgumentError, "Unknown error code: #{code}" if Rails.env.test?

      entry = ErrorCatalogue.fetch("INTERNAL_ERROR")
    end
    http_status = status || entry.status
    error = {
      type: "https://httpstatuses.com/#{http_status}",
      title: entry.title,
      status: http_status,
      code: entry.code,
      detail: detail
    }
    error[:errors] = errors if errors
    error.merge!(extra) if extra.present?
    render json: { success: false, data: nil, error: error, message: detail }, status: http_status
  end
end
