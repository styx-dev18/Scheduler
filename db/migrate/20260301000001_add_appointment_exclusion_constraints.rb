class AddAppointmentExclusionConstraints < ActiveRecord::Migration[8.1]
  ACTIVE = "status IN ('confirmed', 'in_progress')".freeze

  def change
    safety_assured do # appointments is new and constraints are validated at creation
      add_exclusion_constraint :appointments, "service_bay_id WITH =, time_range WITH &&",
                               using: :gist, where: ACTIVE, name: "appointments_no_bay_overlap"
      add_exclusion_constraint :appointments, "technician_id WITH =, time_range WITH &&",
                               using: :gist, where: ACTIVE, name: "appointments_no_technician_overlap"
      add_exclusion_constraint :appointments, "vehicle_id WITH =, time_range WITH &&",
                               using: :gist, where: ACTIVE, name: "appointments_no_vehicle_overlap"
    end
  end
end
