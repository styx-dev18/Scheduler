class TechnicianShift < ApplicationRecord
  belongs_to :technician

  validates :day_of_week, presence: true, inclusion: { in: 0..6 }
  validates :starts_at, :ends_at, presence: true
end
