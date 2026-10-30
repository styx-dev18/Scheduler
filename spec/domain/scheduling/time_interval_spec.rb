require "prop_check"

RSpec.describe Scheduling::TimeInterval do
  def interval(from, to)
    described_class.new(starts_at: Time.utc(2030, 1, 7, *from), ends_at: Time.utc(2030, 1, 7, *to))
  end

  let(:a) { interval([ 10 ], [ 11 ]) }
  let(:b) { interval([ 11 ], [ 12 ]) }
  let(:c) { interval([ 10, 59 ], [ 12 ]) }
  let(:d) { interval([ 10, 15 ], [ 10, 45 ]) }
  let(:f) { described_class.new(starts_at: Time.utc(2030, 1, 7, 23), ends_at: Time.utc(2030, 1, 8)) }
  let(:g) { described_class.new(starts_at: Time.utc(2030, 1, 8), ends_at: Time.utc(2030, 1, 8, 1)) }

  it "does not overlap back-to-back intervals" do
    expect(a.overlaps?(b)).to be false
  end

  it "overlaps by one minute" do
    expect(a.overlaps?(c)).to be true
  end

  it "overlaps and covers a contained interval" do
    expect(a.overlaps?(d)).to be true
    expect(a.cover?(d)).to be true
  end

  it "overlaps an identical interval" do
    expect(a.overlaps?(a)).to be true
  end

  it "does not overlap across midnight adjacency" do
    expect(f.overlaps?(g)).to be false
  end

  it "reports duration in seconds" do
    expect(a.duration).to eq(3600)
  end

  it "is symmetric over all pairs" do
    all = [ a, b, c, d, f, g ]
    all.product(all).each do |x, y|
      expect(x.overlaps?(y)).to eq(y.overlaps?(x))
    end
  end

  it "rejects an end equal to or before the start" do
    start = Time.utc(2030, 1, 7, 10)
    expect { described_class.new(starts_at: start, ends_at: start) }.to raise_error(ArgumentError)
    expect { described_class.new(starts_at: start, ends_at: start - 60) }.to raise_error(ArgumentError)
  end

  it "rejects nil bounds" do
    expect { described_class.new(starts_at: nil, ends_at: Time.utc(2030, 1, 7)) }.to raise_error(ArgumentError)
  end

  describe ".from_slot" do
    let(:slot) { Scheduling::SlotTime.new(starts_at: Time.utc(2030, 1, 7, 10), slot_minutes: 15) }

    it "builds an interval from a duration" do
      expect(described_class.from_slot(slot, duration_minutes: 60)).to eq(a)
    end

    it "rejects a non-positive duration" do
      expect { described_class.from_slot(slot, duration_minutes: 0) }.to raise_error(ArgumentError)
    end
  end

  describe "properties" do
    let(:g) { PropCheck::Generators }
    let(:base) { Time.utc(2030, 1, 7) }

    def build(start_minutes, duration_minutes)
      starts = base + (start_minutes * 60)
      described_class.new(starts_at: starts, ends_at: starts + (duration_minutes * 60))
    end

    it "holds the overlap and cover laws for generated pairs" do
      PropCheck.forall(g.choose(0..2_880), g.choose(1..600), g.choose(0..2_880), g.choose(1..600)) do |s1, d1, s2, d2|
        x = build(s1, d1)
        y = build(s2, d2)

        expect(x.overlaps?(y)).to eq(y.overlaps?(x))
        expect(x.overlaps?(x)).to be true
        expect(x.overlaps?(y)).to be true if x.cover?(y)
        expect(x.cover?(y) && y.cover?(x)).to eq(x == y)
        expect(x.duration).to eq(d1 * 60)
      end
    end

    it "never overlaps back-to-back intervals" do
      PropCheck.forall(g.choose(0..2_880), g.choose(1..600), g.choose(1..600)) do |s, d1, d2|
        x = build(s, d1)
        y = build(s + d1, d2)

        expect(x.overlaps?(y)).to be false
        expect(y.overlaps?(x)).to be false
      end
    end

    it "rejects generated non-positive durations in from_slot" do
      slot = Scheduling::SlotTime.new(starts_at: Time.utc(2030, 1, 7, 10), slot_minutes: 15)

      PropCheck.forall(g.choose(-600..0)) do |minutes|
        expect { described_class.from_slot(slot, duration_minutes: minutes) }.to raise_error(ArgumentError)
      end
    end
  end
end
