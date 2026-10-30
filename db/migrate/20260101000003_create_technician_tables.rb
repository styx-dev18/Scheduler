class CreateTechnicianTables < ActiveRecord::Migration[8.1]
  def change
    create_table :qualifications, id: :uuid do |t|
      t.string :code, null: false
      t.string :name, null: false
      t.timestamps
      t.index :code, unique: true
    end

    create_table :technicians, id: :uuid do |t|
      t.references :dealership, type: :uuid, null: false, foreign_key: true
      t.string :name, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    create_table :technician_qualifications, id: :uuid do |t|
      t.references :technician, type: :uuid, null: false, foreign_key: true
      t.references :qualification, type: :uuid, null: false, foreign_key: true
      t.timestamps
      t.index [ :technician_id, :qualification_id ], unique: true
    end

    create_table :technician_shifts, id: :uuid do |t|
      t.references :technician, type: :uuid, null: false, foreign_key: true
      t.integer :day_of_week, null: false
      t.time :starts_at, null: false
      t.time :ends_at, null: false
      t.timestamps
      t.index [ :technician_id, :day_of_week ]
      t.check_constraint "day_of_week BETWEEN 0 AND 6", name: "technician_shifts_day_of_week_check"
      t.check_constraint "ends_at > starts_at", name: "technician_shifts_ends_after_starts_check"
    end

    create_table :technician_time_off, id: :uuid do |t|
      t.references :technician, type: :uuid, null: false, foreign_key: true
      t.timestamptz :start_at, null: false
      t.timestamptz :end_at, null: false
      t.string :reason
      t.timestamps
      t.index [ :technician_id, :start_at ]
      t.check_constraint "end_at > start_at", name: "technician_time_off_end_after_start_check"
    end

    create_table :bay_blocks, id: :uuid do |t|
      t.references :service_bay, type: :uuid, null: false, foreign_key: true
      t.timestamptz :start_at, null: false
      t.timestamptz :end_at, null: false
      t.string :reason
      t.timestamps
      t.index [ :service_bay_id, :start_at ]
      t.check_constraint "end_at > start_at", name: "bay_blocks_end_after_start_check"
    end
  end
end
