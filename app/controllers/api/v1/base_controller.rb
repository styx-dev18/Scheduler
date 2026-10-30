module Api
  module V1
    class BaseController < ApplicationController
      include Envelope
      include Pagy::Backend

      rescue_from StandardError do |error|
        Rails.logger.error("#{error.class}: #{error.message}")
        render_failure("INTERNAL_ERROR", detail: "An unexpected error occurred")
      end
      rescue_from ActiveRecord::StaleObjectError do
        render_failure("CONCURRENT_MODIFICATION", detail: "The record was modified by another request")
      end
      rescue_from ActiveRecord::RecordInvalid do |error|
        render_failure("VALIDATION_ERROR", detail: error.message, errors: error.record.errors.to_hash)
      end
      rescue_from ActionController::ParameterMissing do |error|
        render_failure("VALIDATION_ERROR", detail: "Missing parameter: #{error.param}",
                       errors: { error.param.to_s => [ "is required" ] }, status: 400)
      end
      rescue_from ActiveRecord::RecordNotFound do |error|
        render_failure(error.model == "Appointment" ? "APPOINTMENT_NOT_FOUND" : "NOT_FOUND", detail: error.message)
      end
      rescue_from Pagy::VariableError do
        render_failure("VALIDATION_ERROR", detail: "Invalid page", errors: { "page" => [ "is invalid" ] }, status: 400)
      end

      private

      def current_customer
        nil
      end

      def pagination_meta(pagy)
        { page: pagy.page, per_page: pagy.limit, total_pages: pagy.pages, total_count: pagy.count }
      end
    end
  end
end
