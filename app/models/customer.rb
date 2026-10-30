class Customer < ApplicationRecord
  has_many :vehicles, dependent: :destroy
  has_many :appointments, dependent: :restrict_with_error

  validates :name, :email, presence: true
  validates :email, uniqueness: { case_sensitive: false }
end
