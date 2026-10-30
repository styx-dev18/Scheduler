module Api
  module V1
    class AppointmentsController < BaseController
      def create
        result = Appointments::IdempotentBook.new.call(key: request.headers["Idempotency-Key"], params: booking_params)

        case result
        in Dry::Monads::Success(body)
          render_success(body, status: :created)
        in Dry::Monads::Failure[ code, details ]
          render_failure(code, detail: details[:detail], errors: details[:errors], extra: details[:extra],
                         status: (400 if code == "VALIDATION_ERROR"))
        end
      end

      private

      def booking_params
        params.permit(:customer_id, :vehicle_id, :service_type_id, :dealership_id, :start_at).to_h
      end
    end
  end
end
