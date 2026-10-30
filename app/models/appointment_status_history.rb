class AppointmentStatusHistory < ApplicationRecord
  belongs_to :appointment

  validates :to_status, :changed_at, presence: true
end
