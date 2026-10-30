RSpec.describe Scheduling::SlotTime do
  it "accepts an aligned start" do
    slot = described_class.new(starts_at: Time.utc(2030, 1, 7, 9, 15), slot_minutes: 15)
    expect(slot.slot_minutes).to eq(15)
  end

  it "rejects an off-grid start" do
    expect { described_class.new(starts_at: Time.utc(2030, 1, 7, 9, 10), slot_minutes: 15) }.to raise_error(ArgumentError)
    expect { described_class.new(starts_at: Time.utc(2030, 1, 7, 9, 0, 30), slot_minutes: 15) }.to raise_error(ArgumentError)
  end

  it "rejects a non-positive or non-integer slot size" do
    time = Time.utc(2030, 1, 7, 9)
    [ 0, -15, 1.5, "15", nil ].each do |size|
      expect { described_class.new(starts_at: time, slot_minutes: size) }.to raise_error(ArgumentError)
    end
  end

  describe ".aligned?" do
    it "checks against the given slot size" do
      expect(described_class.aligned?(Time.utc(2030, 1, 7, 9, 15), 30)).to be false
      expect(described_class.aligned?(Time.utc(2030, 1, 7, 9, 30), 30)).to be true
    end
  end
end
