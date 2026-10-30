require "rails_helper"

RSpec.describe Appointment, ".overlapping" do
  def interval(from, to)
    Scheduling::TimeInterval.new(starts_at: from, ends_at: to)
  end

  let(:a) { interval(Time.utc(2030, 1, 7, 10), Time.utc(2030, 1, 7, 11)) }
  let(:fixtures) do
    [
      interval(Time.utc(2030, 1, 7, 11), Time.utc(2030, 1, 7, 12)),
      interval(Time.utc(2030, 1, 7, 10, 59), Time.utc(2030, 1, 7, 12)),
      interval(Time.utc(2030, 1, 7, 10, 15), Time.utc(2030, 1, 7, 10, 45)),
      a,
      interval(Time.utc(2030, 1, 7, 9), Time.utc(2030, 1, 7, 10)),
      interval(Time.utc(2030, 1, 7, 23), Time.utc(2030, 1, 8, 0)),
      interval(Time.utc(2030, 1, 8, 0), Time.utc(2030, 1, 8, 1))
    ]
  end

  before { create(:appointment, start_at: a.starts_at, end_at: a.ends_at) }

  it "AC2 agrees with TimeInterval#overlaps? for every fixture" do
    fixtures.each do |x|
      expect(described_class.overlapping(x).exists?).to eq(a.overlaps?(x)), "mismatch for #{x}"
    end
  end

  it "AC1 is symmetric over all fixture pairs" do
    fixtures.product(fixtures).each do |x, y|
      expect(x.overlaps?(y)).to eq(y.overlaps?(x))
    end
  end
end
