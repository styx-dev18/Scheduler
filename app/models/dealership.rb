class Dealership < ApplicationRecord
  has_many :opening_hours, class_name: "DealershipOpeningHour", dependent: :destroy
  has_many :holidays, class_name: "DealershipHoliday", dependent: :destroy
  has_many :service_bays, dependent: :destroy
  has_many :technicians, dependent: :destroy
  has_many :appointments, dependent: :restrict_with_error

  validates :name, presence: true
  validates :time_zone, presence: true, inclusion: { in: ActiveSupport::TimeZone::MAPPING.values }
end
