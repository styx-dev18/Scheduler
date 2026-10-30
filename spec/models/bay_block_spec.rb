require "rails_helper"

RSpec.describe BayBlock do
  subject { build(:bay_block) }

  it { is_expected.to belong_to(:service_bay) }
  it { is_expected.to validate_presence_of(:start_at) }
  it { is_expected.to validate_presence_of(:end_at) }

  it "AC5 rejects an end before the start" do
    record = build(:bay_block, start_at: Time.utc(2030, 1, 7, 10), end_at: Time.utc(2030, 1, 7, 9))
    expect(record).not_to be_valid
    expect(record.errors[:end_at]).to be_present
  end

  it "AC5 rejects an empty interval" do
    record = build(:bay_block, start_at: Time.utc(2030, 1, 7, 10), end_at: Time.utc(2030, 1, 7, 10))
    expect(record).not_to be_valid
  end
end
