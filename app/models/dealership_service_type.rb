class DealershipServiceType < ApplicationRecord
  belongs_to :dealership
  belongs_to :service_type

  validates :service_type_id, uniqueness: { scope: :dealership_id }
end
