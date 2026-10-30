class Appointment < ApplicationRecord
  enum :status, {
    confirmed: "confirmed",
    in_progress: "in_progress",
    completed: "completed",
    cancelled: "cancelled",
    no_show: "no_show"
  }, validate: true

  belongs_to :customer
  belongs_to :vehicle
  belongs_to :technician
  belongs_to :service_bay
  belongs_to :service_type
  belongs_to :dealership
  has_many :status_histories, class_name: "AppointmentStatusHistory", dependent: :destroy

  attr_readonly :time_range

  validates :start_at, :end_at, presence: true
  validate :end_after_start
  validate :resources_share_dealership

  scope :active, -> { where(status: %w[confirmed in_progress]) }
  scope :for_vehicle, ->(vehicle) { where(vehicle_id: vehicle) }
  scope :for_technician, ->(technician) { where(technician_id: technician) }
  scope :overlapping, lambda { |interval|
    where("time_range && tstzrange(?, ?, '[)')", interval.starts_at, interval.ends_at)
  }

  private

  def end_after_start
    return if start_at.blank? || end_at.blank? || end_at > start_at

    errors.add(:end_at, "must be after start_at")
  end

  def resources_share_dealership
    return if dealership_id.blank?

    errors.add(:technician, "must belong to the dealership") if technician && technician.dealership_id != dealership_id
    errors.add(:service_bay, "must belong to the dealership") if service_bay && service_bay.dealership_id != dealership_id
  end
end
