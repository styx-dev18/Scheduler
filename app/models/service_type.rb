class ServiceType < ApplicationRecord
  belongs_to :required_qualification, class_name: "Qualification", optional: true
  has_many :appointments, dependent: :restrict_with_error
  has_many :dealership_service_types, dependent: :destroy
  has_many :dealerships, through: :dealership_service_types

  validates :name, presence: true
  validates :duration_minutes, numericality: { only_integer: true, greater_than: 0 }
  validates :required_bay_type, inclusion: { in: ServiceBay::BAY_TYPES }
end
