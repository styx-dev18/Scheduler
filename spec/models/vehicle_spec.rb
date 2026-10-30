require "rails_helper"

RSpec.describe Vehicle do
  subject { build(:vehicle) }

  it { is_expected.to belong_to(:customer) }
  it { is_expected.to have_many(:appointments).dependent(:restrict_with_error) }
  it { is_expected.to validate_presence_of(:vin) }
  it { is_expected.to validate_presence_of(:make) }
  it { is_expected.to validate_presence_of(:model) }
  it { is_expected.to validate_uniqueness_of(:vin) }
end
