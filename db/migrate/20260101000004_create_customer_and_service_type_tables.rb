class CreateCustomerAndServiceTypeTables < ActiveRecord::Migration[8.1]
  def change
    create_table :service_types, id: :uuid do |t|
      t.string :name, null: false
      t.integer :duration_minutes, null: false
      t.references :required_qualification, type: :uuid, foreign_key: { to_table: :qualifications }
      t.string :required_bay_type, null: false, default: "general"
      t.timestamps
      t.check_constraint "duration_minutes > 0", name: "service_types_duration_minutes_check"
      t.check_constraint "required_bay_type IN ('general', 'lift', 'alignment')", name: "service_types_required_bay_type_check"
    end

    create_table :customers, id: :uuid do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.string :phone
      t.timestamps
      t.index :email, unique: true
    end

    create_table :vehicles, id: :uuid do |t|
      t.references :customer, type: :uuid, null: false, foreign_key: true
      t.string :vin, null: false
      t.string :make, null: false
      t.string :model, null: false
      t.integer :year
      t.string :license_plate
      t.timestamps
      t.index :vin, unique: true
    end
  end
end
