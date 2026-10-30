class ServiceBay < ApplicationRecord
  BAY_TYPES = %w[general lift alignment].freeze

  belongs_to :dealership
  has_many :bay_blocks, dependent: :destroy
  has_many :appointments, dependent: :restrict_with_error

  validates :name, presence: true
  validates :bay_type, inclusion: { in: BAY_TYPES }
end
