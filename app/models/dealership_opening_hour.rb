class DealershipOpeningHour < ApplicationRecord
  belongs_to :dealership

  validates :day_of_week, presence: true, inclusion: { in: 0..6 }
  validates :opens_at, :closes_at, presence: true
end
