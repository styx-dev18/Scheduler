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
  has_many :reschedules, class_name: "AppointmentReschedule", dependent: :destroy

  MAX_REASON_LENGTH = 500

  attr_readonly :time_range

  validates :start_at, :end_at, presence: true
  validates :cancellation_reason, length: { maximum: MAX_REASON_LENGTH }, allow_nil: true
  validate :end_after_start
  validate :resources_share_dealership

  scope :active, -> { where(status: %w[confirmed in_progress]) }
  scope :for_vehicle, ->(vehicle) { where(vehicle_id: vehicle) }
  scope :for_technician, ->(technician) { where(technician_id: technician) }
  scope :overlapping, lambda { |interval|
    where("time_range && tstzrange(?, ?, '[)')", interval.starts_at, interval.ends_at)
  }

  def self.build_confirmed(**attrs)
    new(**attrs, status: "confirmed")
  end

  def start!(at:, actor:)
    transition_to!("in_progress", at:, actor:)
  end

  def complete!(at:, actor:)
    transition_to!("completed", at:, actor:)
  end

  def mark_no_show!(at:, actor:)
    transition_to!("no_show", at:, actor:)
  end

  def cancel!(at:, actor:, reason: nil)
    transition_to!("cancelled", at:, actor:, cancelled_at: at, cancellation_reason: reason)
  end

  private

  def transition_to!(to, at:, actor:, **attributes)
    unless Scheduling::StatusMachine.allowed?(from: status, to:)
      raise Scheduling::StatusMachine::InvalidTransition, "#{status} -> #{to}"
    end

    transaction do
      from = status
      update!(status: to, **attributes)
      status_histories.create!(from_status: from, to_status: to, changed_at: at, actor:)
    end
    self
  end

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
