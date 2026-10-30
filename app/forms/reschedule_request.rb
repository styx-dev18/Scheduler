class RescheduleRequest
  include ActiveModel::Model

  attr_accessor :new_start_at, :lock_version

  validates :new_start_at, presence: true
  validate :new_start_at_is_iso8601
  validates :lock_version, format: { with: /\A\d+\z/, message: "must be a non-negative integer" }, allow_blank: true

  def starts_at
    Time.iso8601(new_start_at).utc
  end

  def expected_lock_version
    Integer(lock_version.to_s, 10) if lock_version.present?
  end

  private

  def new_start_at_is_iso8601
    return if new_start_at.blank?
    return if new_start_at.is_a?(String) && new_start_at.match?(BookingRequest::OFFSET_FORMAT) && parsable?

    errors.add(:new_start_at, "must be an ISO-8601 timestamp with a UTC offset")
  end

  def parsable?
    Time.iso8601(new_start_at)
    true
  rescue ArgumentError
    false
  end
end
