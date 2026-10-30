class AddDescriptionToServiceTypes < ActiveRecord::Migration[8.1]
  def change
    add_column :service_types, :description, :text
  end
end
