module Api
  module V1
    class AvailabilityController < BaseController
      def index
        form = AvailabilityRequest.new(availability_params)
        unless form.valid?
          return render_failure("VALIDATION_ERROR", detail: "Invalid availability request",
                                errors: form.errors.to_hash, status: 400)
        end

        dealership = Dealership.find(form.dealership_id)
        service_type = ServiceType.find(form.service_type_id)
        date = form.local_date
        cache_key = [ "availability", dealership.id, service_type.id, date.iso8601 ]
        body = Rails.cache.fetch(cache_key, expires_in: 30.seconds) do
          slots = Availability::DaySlots.new.call(dealership:, service_type:, date:)
          {
            dealership_id: dealership.id,
            service_type_id: service_type.id,
            date: date.iso8601,
            time_zone: dealership.time_zone,
            slots: AvailabilitySlotSerializer.new(slots, params: { time_zone: dealership.time_zone }).serializable_hash
          }
        end
        render_success(body)
      end

      private

      def availability_params
        params.permit(:dealership_id, :service_type_id, :date).to_h
      end
    end
  end
end
