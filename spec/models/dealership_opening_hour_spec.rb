require "rails_helper"

RSpec.describe DealershipOpeningHour do
  subject { build(:dealership_opening_hour) }

  it { is_expected.to belong_to(:dealership) }
  it { is_expected.to validate_presence_of(:day_of_week) }
  it { is_expected.to validate_inclusion_of(:day_of_week).in_range(0..6) }
  it { is_expected.to validate_presence_of(:opens_at) }
  it { is_expected.to validate_presence_of(:closes_at) }
end
