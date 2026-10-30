require "rails_helper"

RSpec.describe TechnicianShift do
  subject { build(:technician_shift) }

  it { is_expected.to belong_to(:technician) }
  it { is_expected.to validate_presence_of(:day_of_week) }
  it { is_expected.to validate_inclusion_of(:day_of_week).in_range(0..6) }
  it { is_expected.to validate_presence_of(:starts_at) }
  it { is_expected.to validate_presence_of(:ends_at) }
end
