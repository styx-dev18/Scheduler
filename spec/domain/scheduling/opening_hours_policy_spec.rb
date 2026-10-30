require "tzinfo"

RSpec.describe Scheduling::OpeningHoursPolicy do
  let(:london) { TZInfo::Timezone.get("Europe/London") }
  let(:new_york) { TZInfo::Timezone.get("America/New_York") }
  let(:monday_hours) { [ { day_of_week: 1, opens_at: "08:00", closes_at: "17:00" } ] }

  def interval(starts_at, ends_at)
    Scheduling::TimeInterval.new(starts_at:, ends_at:)
  end

  def policy(zone: london, opening_hours: monday_hours, holidays: [])
    described_class.new(zone:, opening_hours:, holidays:)
  end

  it "is open when starting exactly at opening" do
    expect(policy.evaluate(interval(Time.utc(2030, 1, 7, 8), Time.utc(2030, 1, 7, 9)))).to eq(:open)
  end

  it "is open when ending exactly at closing" do
    expect(policy.evaluate(interval(Time.utc(2030, 1, 7, 16), Time.utc(2030, 1, 7, 17)))).to eq(:open)
  end

  it "is outside hours when ending one minute after closing" do
    expect(policy.evaluate(interval(Time.utc(2030, 1, 7, 16, 1), Time.utc(2030, 1, 7, 17, 1)))).to eq(:outside_hours)
  end

  it "is outside hours when starting before opening" do
    expect(policy.evaluate(interval(Time.utc(2030, 1, 7, 7), Time.utc(2030, 1, 7, 8)))).to eq(:outside_hours)
  end

  it "is closed on a holiday, even outside hours" do
    holiday_policy = policy(holidays: [ Date.new(2030, 1, 7) ])

    expect(holiday_policy.evaluate(interval(Time.utc(2030, 1, 7, 9), Time.utc(2030, 1, 7, 10)))).to eq(:closed)
    expect(holiday_policy.evaluate(interval(Time.utc(2030, 1, 7, 18), Time.utc(2030, 1, 7, 19)))).to eq(:closed)
  end

  it "is closed on a weekday with no hours" do
    expect(policy.evaluate(interval(Time.utc(2030, 1, 6, 9), Time.utc(2030, 1, 6, 10)))).to eq(:closed)
  end

  it "is outside hours when the local end falls on a later date" do
    late = policy(opening_hours: [ { day_of_week: 1, opens_at: "08:00", closes_at: "23:59" } ])

    expect(late.evaluate(interval(Time.utc(2030, 1, 7, 23, 30), Time.utc(2030, 1, 8, 0, 30)))).to eq(:outside_hours)
  end

  it "requires the interval to fit inside a single window" do
    split = policy(opening_hours: [
      { day_of_week: 1, opens_at: "08:00", closes_at: "12:00" },
      { day_of_week: 1, opens_at: "13:00", closes_at: "17:00" }
    ])

    expect(split.evaluate(interval(Time.utc(2030, 1, 7, 11, 30), Time.utc(2030, 1, 7, 13, 30)))).to eq(:outside_hours)
    expect(split.evaluate(interval(Time.utc(2030, 1, 7, 13), Time.utc(2030, 1, 7, 14)))).to eq(:open)
  end

  it "handles the DST day in local time" do
    sunday = policy(opening_hours: [ { day_of_week: 0, opens_at: "08:00", closes_at: "17:00" } ])

    expect(sunday.evaluate(interval(Time.utc(2030, 3, 31, 7), Time.utc(2030, 3, 31, 8)))).to eq(:open)
    expect(sunday.evaluate(interval(Time.utc(2030, 3, 31, 15, 30), Time.utc(2030, 3, 31, 16, 30)))).to eq(:outside_hours)
  end

  it "evaluates two zones at the same UTC instant" do
    instant = interval(Time.utc(2030, 1, 7, 13, 30), Time.utc(2030, 1, 7, 14, 30))
    new_york_policy = policy(zone: new_york, opening_hours: [ { day_of_week: 1, opens_at: "09:00", closes_at: "17:00" } ])

    expect(policy.evaluate(instant)).to eq(:open)
    expect(new_york_policy.evaluate(instant)).to eq(:outside_hours)
  end
end
