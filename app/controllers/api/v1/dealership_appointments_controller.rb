module Api
  module V1
    class DealershipAppointmentsController < BaseController
      def index
        form = DealershipScheduleRequest.new(schedule_params)
        unless form.valid?
          return render_failure("VALIDATION_ERROR", detail: "Invalid schedule request",
                                errors: form.errors.to_hash, status: 400)
        end

        dealership = Dealership.find(form.dealership_id)
        query = Appointments::ListQuery.new.call(**form.filters(dealership.time_zone))
        pagy, records = pagy(query, limit: form.limit)
        render_success(AppointmentSerializer.new(records).serializable_hash, meta: pagination_meta(pagy))
      end

      private

      def schedule_params
        params.permit(:dealership_id, :date, :technician_id, :service_bay_id, :status, :per_page).to_h
      end
    end
  end
end
