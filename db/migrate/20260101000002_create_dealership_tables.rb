class CreateDealershipTables < ActiveRecord::Migration[8.1]
  def change
    create_table :dealerships, id: :uuid do |t|
      t.string :name, null: false
      t.string :time_zone, null: false
      t.timestamps
    end

    create_table :dealership_opening_hours, id: :uuid do |t|
      t.references :dealership, type: :uuid, null: false, foreign_key: true
      t.integer :day_of_week, null: false
      t.time :opens_at, null: false
      t.time :closes_at, null: false
      t.timestamps
      t.index [ :dealership_id, :day_of_week ]
      t.check_constraint "day_of_week BETWEEN 0 AND 6", name: "dealership_opening_hours_day_of_week_check"
      t.check_constraint "closes_at > opens_at", name: "dealership_opening_hours_closes_after_opens_check"
    end

    create_table :dealership_holidays, id: :uuid do |t|
      t.references :dealership, type: :uuid, null: false, foreign_key: true
      t.date :holiday_on, null: false
      t.string :name, null: false
      t.timestamps
      t.index [ :dealership_id, :holiday_on ], unique: true
    end

    create_table :service_bays, id: :uuid do |t|
      t.references :dealership, type: :uuid, null: false, foreign_key: true
      t.string :name, null: false
      t.string :bay_type, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
      t.index [ :dealership_id, :bay_type ]
      t.check_constraint "bay_type IN ('general', 'lift', 'alignment')", name: "service_bays_bay_type_check"
    end
  end
end
