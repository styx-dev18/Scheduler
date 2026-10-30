module Api
  module V1
    class AppointmentsController < BaseController
      before_action :require_uuid_id, only: %i[show cancel reschedule update_status]

      def create
        result = Appointments::IdempotentBook.new.call(key: request.headers["Idempotency-Key"], params: booking_params)

        case result
        in Dry::Monads::Success(body)
          response.headers["Location"] = api_v1_appointment_url(body.with_indifferent_access.fetch(:id))
          render_success(body, status: :created)
        in Dry::Monads::Failure[ code, details ]
          render_service_failure(code, details)
        end
      end

      def show
        appointment = Appointment.includes(*Appointments::ListQuery::INCLUDES).find(params[:id])
        render_success(AppointmentSerializer.new(appointment).serializable_hash)
      end

      def index
        form = AppointmentListRequest.new(list_params)
        unless form.valid?
          return render_failure("VALIDATION_ERROR", detail: "Invalid appointment list request",
                                errors: form.errors.to_hash, status: 400)
        end

        pagy, records = pagy(Appointments::ListQuery.new.call(**form.filters), limit: form.limit)
        render_success(AppointmentSerializer.new(records).serializable_hash, meta: pagination_meta(pagy))
      end

      def cancel
        render_appointment_result(
          Appointments::Cancel.new.call(appointment_id: params[:id], reason: params.permit(:reason)[:reason])
        )
      end

      def reschedule
        render_appointment_result(
          Appointments::Reschedule.new.call(appointment_id: params[:id],
                                            params: params.permit(:new_start_at, :lock_version).to_h)
        )
      end

      def update_status
        render_appointment_result(
          Appointments::ChangeStatus.new.call(appointment_id: params[:id], status: params.require(:status))
        )
      end

      private

      def require_uuid_id
        return if BookingRequest::UUID_FORMAT.match?(params[:id].to_s)

        render_failure("VALIDATION_ERROR", detail: "Invalid appointment id",
                       errors: { "id" => [ "is not a valid UUID" ] }, status: 400)
      end

      def render_appointment_result(result)
        case result
        in Dry::Monads::Success(appointment)
          render_success(AppointmentSerializer.new(appointment).serializable_hash)
        in Dry::Monads::Failure[ code, details ]
          render_service_failure(code, details)
        end
      end

      def render_service_failure(code, details)
        render_failure(code, detail: details[:detail], errors: details[:errors], extra: details[:extra],
                       status: (400 if code == "VALIDATION_ERROR"))
      end

      def list_params
        params.permit(:customer_id, :status, :from, :to, :sort, :per_page).to_h
      end

      def booking_params
        params.permit(:customer_id, :vehicle_id, :service_type_id, :dealership_id, :start_at).to_h
      end
    end
  end
end
