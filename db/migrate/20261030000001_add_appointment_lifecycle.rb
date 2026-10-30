class AddAppointmentLifecycle < ActiveRecord::Migration[8.1]
  def change
    add_column :appointments, :cancelled_at, :timestamptz
    add_column :appointments, :cancellation_reason, :text
    add_column :appointment_status_histories, :actor, :string

    create_table :appointment_reschedules, id: :uuid do |t|
      t.references :appointment, type: :uuid, null: false, foreign_key: true
      t.timestamptz :prev_start_at, null: false
      t.timestamptz :prev_end_at, null: false
      t.timestamptz :new_start_at, null: false
      t.timestamptz :new_end_at, null: false
      t.string :actor
      t.string :request_id
      t.timestamps

      t.check_constraint "prev_end_at > prev_start_at", name: "appointment_reschedules_prev_end_after_start_check"
      t.check_constraint "new_end_at > new_start_at", name: "appointment_reschedules_new_end_after_start_check"
    end
  end
end
