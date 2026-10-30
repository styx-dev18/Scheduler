class CreateAppointments < ActiveRecord::Migration[8.1]
  def change
    create_table :appointments, id: :uuid do |t|
      t.references :customer, type: :uuid, null: false, foreign_key: true, index: false
      t.references :vehicle, type: :uuid, null: false, foreign_key: true, index: false
      t.references :technician, type: :uuid, null: false, foreign_key: true, index: false
      t.references :service_bay, type: :uuid, null: false, foreign_key: true, index: false
      t.references :service_type, type: :uuid, null: false, foreign_key: true
      t.references :dealership, type: :uuid, null: false, foreign_key: true, index: false
      t.timestamptz :start_at, null: false
      t.timestamptz :end_at, null: false
      t.string :status, null: false, default: "confirmed"
      t.integer :lock_version, null: false, default: 0
      t.virtual :time_range, type: :tstzrange, as: "tstzrange(start_at, end_at, '[)')", stored: true
      t.timestamps
      t.index [ :service_bay_id, :time_range ], using: :gist
      t.index [ :technician_id, :time_range ], using: :gist
      t.index [ :vehicle_id, :start_at ]
      t.index [ :dealership_id, :start_at ]
      t.index [ :customer_id, :start_at ]
      t.check_constraint "end_at > start_at", name: "appointments_end_after_start_check"
      t.check_constraint "status IN ('confirmed', 'in_progress', 'completed', 'cancelled', 'no_show')", name: "appointments_status_check"
    end

    create_table :appointment_status_histories, id: :uuid do |t|
      t.references :appointment, type: :uuid, null: false, foreign_key: true
      t.string :from_status
      t.string :to_status, null: false
      t.timestamptz :changed_at, null: false
      t.timestamps
    end

    create_table :idempotency_keys, id: :uuid do |t|
      t.string :key, null: false
      t.string :request_fingerprint, null: false
      t.references :appointment, type: :uuid, foreign_key: true
      t.integer :response_status
      t.jsonb :response_body
      t.timestamps
      t.index :key, unique: true
    end
  end
end
