class AppointmentSerializer
  include Alba::Resource

  attributes :id, :status, :customer_id, :vehicle_id, :service_type_id, :dealership_id, :technician_id, :service_bay_id

  attribute :start_at do |appointment|
    appointment.start_at.utc.iso8601
  end

  attribute :end_at do |appointment|
    appointment.end_at.utc.iso8601
  end
end
