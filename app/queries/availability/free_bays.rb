module Availability
  class FreeBays
    TRACER = OpenTelemetry.tracer_provider.tracer("scheduler.availability")

    def initialize(dealership:, service_type:, interval:, exclude_appointment_id: nil)
      @dealership = dealership
      @service_type = service_type
      @interval = interval
      @exclude_appointment_id = exclude_appointment_id
    end

    def call
      query
    end

    def ids
      TRACER.in_span("availability.free_bays", attributes: span_attributes) { query.pluck(:id) }
    end

    private

    def span_attributes
      { "dealership.id" => @dealership.id, "service_type.id" => @service_type.id }
    end

    def query
      @dealership.service_bays
        .where(active: true, bay_type: @service_type.required_bay_type)
        .where.not(id: Appointment.active.overlapping(@interval).where.not(id: @exclude_appointment_id).select(:service_bay_id))
        .where.not(id: BayBlock.where("start_at < ? AND end_at > ?", @interval.ends_at, @interval.starts_at).select(:service_bay_id))
        .order(:id)
    end
  end
end
