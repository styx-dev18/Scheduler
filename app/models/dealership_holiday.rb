class DealershipHoliday < ApplicationRecord
  belongs_to :dealership

  validates :holiday_on, :name, presence: true
  validates :holiday_on, uniqueness: { scope: :dealership_id }
end
