require "rails_helper"

RSpec.describe RescheduleRequest do
  it "EC5 is valid with an ISO-8601 timestamp with offset" do
    expect(described_class.new(new_start_at: "2030-01-08T11:00:00Z")).to be_valid
  end

  it "EC5 requires new_start_at" do
    form = described_class.new({})

    expect(form).not_to be_valid
    expect(form.errors[:new_start_at]).to be_present
  end

  it "EC5 rejects a timestamp without an offset" do
    form = described_class.new(new_start_at: "2030-01-08T11:00:00")
    form.valid?

    expect(form.errors[:new_start_at]).to eq([ "must be an ISO-8601 timestamp with a UTC offset" ])
  end

  it "EC5 rejects a non-string timestamp" do
    form = described_class.new(new_start_at: 12_345)

    expect(form).not_to be_valid
  end

  it "EC5 rejects an impossible date" do
    form = described_class.new(new_start_at: "2030-13-45T11:00:00Z")

    expect(form).not_to be_valid
  end

  it "EC7 accepts lock_version as an integer or a numeric string" do
    expect(described_class.new(new_start_at: "2030-01-08T11:00:00Z", lock_version: 0)).to be_valid
    expect(described_class.new(new_start_at: "2030-01-08T11:00:00Z", lock_version: "3")).to be_valid
  end

  it "EC7 rejects a non-numeric or negative lock_version" do
    %w[abc -1 1.5].each do |value|
      form = described_class.new(new_start_at: "2030-01-08T11:00:00Z", lock_version: value)

      expect(form).not_to be_valid, value
      expect(form.errors[:lock_version]).to be_present
    end
  end

  it "AC4 returns starts_at in UTC" do
    form = described_class.new(new_start_at: "2030-01-08T12:00:00+01:00")

    expect(form.starts_at).to eq(Time.utc(2030, 1, 8, 11))
    expect(form.starts_at).to be_utc
  end

  it "EC7 returns expected_lock_version as an Integer or nil" do
    expect(described_class.new(lock_version: "4").expected_lock_version).to eq(4)
    expect(described_class.new(lock_version: 0).expected_lock_version).to eq(0)
    expect(described_class.new(lock_version: "").expected_lock_version).to be_nil
    expect(described_class.new({}).expected_lock_version).to be_nil
  end
end
