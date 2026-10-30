class AppointmentReschedule < ApplicationRecord
  belongs_to :appointment

  validates :prev_start_at, :prev_end_at, :new_start_at, :new_end_at, presence: true
  validate :prev_end_after_prev_start
  validate :new_end_after_new_start

  private

  def prev_end_after_prev_start
    return if prev_start_at.blank? || prev_end_at.blank?

    errors.add(:prev_end_at, "must be after prev_start_at") unless prev_end_at > prev_start_at
  end

  def new_end_after_new_start
    return if new_start_at.blank? || new_end_at.blank?

    errors.add(:new_end_at, "must be after new_start_at") unless new_end_at > new_start_at
  end
end
