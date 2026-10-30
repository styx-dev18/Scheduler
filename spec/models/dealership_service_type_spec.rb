require "rails_helper"

RSpec.describe DealershipServiceType do
  subject { build(:dealership_service_type) }

  it { is_expected.to belong_to(:dealership) }
  it { is_expected.to belong_to(:service_type) }

  it "rejects a duplicate dealership and service type pair" do
    existing = create(:dealership_service_type)
    duplicate = build(:dealership_service_type, dealership: existing.dealership, service_type: existing.service_type)

    expect(duplicate).not_to be_valid
  end
end
