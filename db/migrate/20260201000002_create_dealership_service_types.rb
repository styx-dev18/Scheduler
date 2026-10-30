class CreateDealershipServiceTypes < ActiveRecord::Migration[8.1]
  def change
    create_table :dealership_service_types, id: :uuid do |t|
      t.references :dealership, type: :uuid, null: false, foreign_key: true, index: false
      t.references :service_type, type: :uuid, null: false, foreign_key: true
      t.timestamps
      t.index [ :dealership_id, :service_type_id ], unique: true
    end
  end
end
