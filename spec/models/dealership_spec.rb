require "rails_helper"

RSpec.describe Dealership do
  subject { build(:dealership) }

  it { is_expected.to have_many(:opening_hours).class_name("DealershipOpeningHour").dependent(:destroy) }
  it { is_expected.to have_many(:holidays).class_name("DealershipHoliday").dependent(:destroy) }
  it { is_expected.to have_many(:service_bays).dependent(:destroy) }
  it { is_expected.to have_many(:technicians).dependent(:destroy) }
  it { is_expected.to have_many(:appointments).dependent(:restrict_with_error) }
  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_presence_of(:time_zone) }

  it "AC5 rejects an unknown time zone" do
    expect(build(:dealership, time_zone: "Mars/Base")).not_to be_valid
  end

  it "accepts UTC and America/Detroit" do
    expect(build(:dealership, time_zone: "UTC")).to be_valid
    expect(build(:dealership, time_zone: "America/Detroit")).to be_valid
  end

  it "rejects Mars/Olympus" do
    expect(build(:dealership, time_zone: "Mars/Olympus")).not_to be_valid
  end
end
