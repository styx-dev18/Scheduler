require "rails_helper"

RSpec.describe Customer do
  subject { build(:customer) }

  it { is_expected.to have_many(:vehicles).dependent(:destroy) }
  it { is_expected.to have_many(:appointments).dependent(:restrict_with_error) }
  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_presence_of(:email) }
  it { is_expected.to validate_uniqueness_of(:email).case_insensitive }
end
