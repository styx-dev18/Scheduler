class AvailabilityRequest
  include ActiveModel::Model

  DATE_FORMAT = /\A\d{4}-\d{2}-\d{2}\z/
  ID_FIELDS = %i[dealership_id service_type_id].freeze

  attr_accessor :dealership_id, :service_type_id, :date

  validates(*ID_FIELDS, presence: true)
  validates(*ID_FIELDS, format: { with: BookingRequest::UUID_FORMAT, message: "is not a valid UUID" }, allow_blank: true)
  validates :date, presence: true
  validate :date_is_iso8601

  def local_date
    Date.iso8601(date)
  end

  private

  def date_is_iso8601
    return if date.blank?
    return if date.is_a?(String) && date.match?(DATE_FORMAT) && parsable?

    errors.add(:date, "must be a date in YYYY-MM-DD format")
  end

  def parsable?
    Date.iso8601(date)
    true
  rescue ArgumentError
    false
  end
end
