require "rails_helper"

RSpec.describe ServiceBay do
  subject { build(:service_bay) }

  it { is_expected.to belong_to(:dealership) }
  it { is_expected.to have_many(:bay_blocks).dependent(:destroy) }
  it { is_expected.to have_many(:appointments).dependent(:restrict_with_error) }
  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_inclusion_of(:bay_type).in_array(%w[general lift alignment]) }
end
