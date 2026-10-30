module Appointments
  class ListQuery
    INCLUDES = %i[customer vehicle service_type dealership technician service_bay].freeze

    def call(customer_id: nil, dealership_id: nil, technician_id: nil, service_bay_id: nil, status: nil, from: nil, to: nil, direction: :asc)
      scope = Appointment.all
      scope = scope.where(customer_id:) if customer_id
      scope = scope.where(dealership_id:) if dealership_id
      scope = scope.where(technician_id:) if technician_id
      scope = scope.where(service_bay_id:) if service_bay_id
      scope = scope.where(status:) if status
      scope = scope.where(start_at: from..) if from
      scope = scope.where(start_at: ...to) if to
      scope.includes(*INCLUDES).order(start_at: direction, id: direction)
    end
  end
end
