require "rails_helper"

RSpec.describe IdempotencyKey do
  subject { build(:idempotency_key) }

  it { is_expected.to belong_to(:appointment).optional }
  it { is_expected.to validate_presence_of(:key) }
  it { is_expected.to validate_presence_of(:request_fingerprint) }
  it { is_expected.to validate_uniqueness_of(:key) }
end
