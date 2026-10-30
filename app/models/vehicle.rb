class Vehicle < ApplicationRecord
  belongs_to :customer
  has_many :appointments, dependent: :restrict_with_error

  validates :vin, :make, :model, presence: true
  validates :vin, uniqueness: true
end
