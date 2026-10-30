class AppointmentListRequest
  include ActiveModel::Model

  MAX_PER_PAGE = 100
  SORTS = %w[asc desc].freeze

  attr_accessor :customer_id, :status, :from, :to, :sort, :per_page

  validates :customer_id, presence: true
  validates :customer_id, format: { with: BookingRequest::UUID_FORMAT, message: "is not a valid UUID" }, allow_blank: true
  validates :status, inclusion: { in: ->(_) { Appointment.statuses.keys } }, allow_blank: true
  validates :sort, inclusion: { in: SORTS }, allow_blank: true
  validates :per_page, format: { with: /\A\d+\z/, message: "must be a positive integer" }, allow_blank: true
  validate :per_page_is_positive
  validate :from_is_iso8601
  validate :to_is_iso8601
  validate :to_is_after_from

  def filters
    {
      customer_id:,
      status: status.presence,
      from: parse(from),
      to: parse(to),
      direction: sort.presence&.to_sym || :asc
    }
  end

  def limit
    [ per_page.presence&.to_i || Pagy::DEFAULT[:limit], MAX_PER_PAGE ].min
  end

  private

  def per_page_is_positive
    return unless per_page.to_s.match?(/\A\d+\z/)
    return if per_page.to_i >= 1

    errors.add(:per_page, "must be a positive integer")
  end

  def from_is_iso8601
    errors.add(:from, "must be an ISO-8601 timestamp with a UTC offset") unless valid_instant?(from)
  end

  def to_is_iso8601
    errors.add(:to, "must be an ISO-8601 timestamp with a UTC offset") unless valid_instant?(to)
  end

  def to_is_after_from
    return if from.blank? || to.blank? || !valid_instant?(from) || !valid_instant?(to)
    return if parse(to) > parse(from)

    errors.add(:to, "must be after from")
  end

  def valid_instant?(value)
    return true if value.blank?

    value.is_a?(String) && value.match?(BookingRequest::OFFSET_FORMAT) && !parse(value).nil?
  end

  def parse(value)
    return if value.blank?

    Time.iso8601(value).utc
  rescue ArgumentError
    nil
  end
end
