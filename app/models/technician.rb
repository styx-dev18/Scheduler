class Technician < ApplicationRecord
  belongs_to :dealership
  has_many :technician_qualifications, dependent: :destroy
  has_many :qualifications, through: :technician_qualifications
  has_many :technician_shifts, dependent: :destroy
  has_many :technician_time_offs, dependent: :destroy
  has_many :appointments, dependent: :restrict_with_error

  validates :name, presence: true
end
