class AppointmentSerializer
  include Alba::Resource

  attributes :id, :status, :customer_id, :vehicle_id, :service_type_id, :dealership_id, :technician_id, :service_bay_id

  attribute :start_at do |appointment|
    appointment.start_at.utc.iso8601
  end

  attribute :end_at do |appointment|
    appointment.end_at.utc.iso8601
  end

  attribute :time_zone do |appointment|
    appointment.dealership.time_zone
  end

  attribute :local_start_at do |appointment|
    appointment.start_at.in_time_zone(appointment.dealership.time_zone).iso8601
  end

  attribute :local_end_at do |appointment|
    appointment.end_at.in_time_zone(appointment.dealership.time_zone).iso8601
  end

  attributes :lock_version, :cancellation_reason

  attribute :cancelled_at do |appointment|
    appointment.cancelled_at&.utc&.iso8601
  end

  attribute :customer do |appointment|
    { id: appointment.customer.id, name: appointment.customer.name }
  end

  attribute :vehicle do |appointment|
    vehicle = appointment.vehicle
    { id: vehicle.id, make: vehicle.make, model: vehicle.model, year: vehicle.year, license_plate: vehicle.license_plate }
  end

  attribute :service_type do |appointment|
    service_type = appointment.service_type
    { id: service_type.id, name: service_type.name, duration_minutes: service_type.duration_minutes }
  end

  attribute :dealership do |appointment|
    { id: appointment.dealership.id, name: appointment.dealership.name }
  end

  attribute :technician do |appointment|
    { id: appointment.technician.id, display_name: appointment.technician.name }
  end

  attribute :service_bay do |appointment|
    { id: appointment.service_bay.id, label: appointment.service_bay.name }
  end
end
