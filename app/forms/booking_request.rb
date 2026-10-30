class BookingRequest
  include ActiveModel::Model

  UUID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
  OFFSET_FORMAT = /(Z|[+-]\d{2}:\d{2})\z/
  ID_FIELDS = %i[customer_id vehicle_id service_type_id dealership_id].freeze

  attr_accessor :customer_id, :vehicle_id, :service_type_id, :dealership_id, :start_at

  validates(*ID_FIELDS, presence: true)
  validates(*ID_FIELDS, format: { with: UUID_FORMAT, message: "is not a valid UUID" }, allow_blank: true)
  validates :start_at, presence: true
  validate :start_at_is_iso8601

  def starts_at
    Time.iso8601(start_at).utc
  end

  private

  def start_at_is_iso8601
    return if start_at.blank?
    return if start_at.is_a?(String) && start_at.match?(OFFSET_FORMAT) && parsable?

    errors.add(:start_at, "must be an ISO-8601 timestamp with a UTC offset")
  end

  def parsable?
    Time.iso8601(start_at)
    true
  rescue ArgumentError
    false
  end
end
