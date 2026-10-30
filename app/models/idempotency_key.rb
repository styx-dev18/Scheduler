class IdempotencyKey < ApplicationRecord
  belongs_to :appointment, optional: true

  validates :key, :request_fingerprint, presence: true
  validates :key, uniqueness: true
end
