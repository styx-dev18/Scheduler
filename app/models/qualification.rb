class Qualification < ApplicationRecord
  has_many :technician_qualifications, dependent: :destroy
  has_many :technicians, through: :technician_qualifications
  has_many :service_types, foreign_key: :required_qualification_id, inverse_of: :required_qualification, dependent: :restrict_with_error

  validates :code, :name, presence: true
  validates :code, uniqueness: true
end
