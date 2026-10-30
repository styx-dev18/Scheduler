class DealershipScheduleRequest
  include ActiveModel::Model
  include PaginatedRequest

  ID_FIELDS = %i[technician_id service_bay_id].freeze

  attr_accessor :dealership_id, :date, :technician_id, :service_bay_id, :status

  validates :dealership_id, presence: true
  validates :dealership_id, format: { with: BookingRequest::UUID_FORMAT, message: "is not a valid UUID" }, allow_blank: true
  validates(*ID_FIELDS, format: { with: BookingRequest::UUID_FORMAT, message: "is not a valid UUID" }, allow_blank: true)
  validates :status, inclusion: { in: ->(_) { Appointment.statuses.keys } }, allow_blank: true
  validate :date_is_iso8601

  def filters(time_zone)
    from, to = day_bounds(time_zone)
    {
      dealership_id:,
      technician_id: technician_id.presence,
      service_bay_id: service_bay_id.presence,
      status: status.presence,
      from:,
      to:,
      direction: :asc
    }
  end

  private

  def day_bounds(time_zone)
    return [ nil, nil ] if date.blank?

    zone = ActiveSupport::TimeZone[time_zone]
    day = Date.iso8601(date)
    next_day = day + 1
    [ zone.local(day.year, day.month, day.day), zone.local(next_day.year, next_day.month, next_day.day) ]
  end

  def date_is_iso8601
    return if date.blank?
    return if date.is_a?(String) && date.match?(AvailabilityRequest::DATE_FORMAT) && parsable?

    errors.add(:date, "must be a date in YYYY-MM-DD format")
  end

  def parsable?
    Date.iso8601(date)
    true
  rescue ArgumentError
    false
  end
end
