require "rails_helper"

RSpec.describe ServiceType do
  subject { build(:service_type) }

  it { is_expected.to belong_to(:required_qualification).class_name("Qualification").optional }
  it { is_expected.to have_many(:appointments).dependent(:restrict_with_error) }
  it { is_expected.to have_many(:dealership_service_types).dependent(:destroy) }
  it { is_expected.to have_many(:dealerships).through(:dealership_service_types) }
  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_numericality_of(:duration_minutes).only_integer.is_greater_than(0) }
  it { is_expected.to validate_inclusion_of(:required_bay_type).in_array(%w[general lift alignment]) }
end
