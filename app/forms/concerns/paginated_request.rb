module PaginatedRequest
  extend ActiveSupport::Concern

  MAX_PER_PAGE = 100

  included do
    attr_accessor :per_page

    validates :per_page, format: { with: /\A\d+\z/, message: "must be a positive integer" }, allow_blank: true
    validate :per_page_is_positive
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
end
