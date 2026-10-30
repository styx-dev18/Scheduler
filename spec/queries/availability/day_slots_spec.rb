require "rails_helper"

RSpec.describe Availability::DaySlots do
  let(:clock) { double("Clock", now: Time.utc(2030, 1, 1)) }
  let(:dealership) { create(:dealership) }
  let(:qualification) { create(:qualification) }
  let(:service_type) { create(:service_type, required_qualification: qualification) }
  let(:date) { Date.new(2030, 1, 7) }
  let!(:bay) { create(:service_bay, dealership:) }
  let!(:tech) { create(:technician, dealership:) }

  subject(:slots) { described_class.new(clock:, slot_minutes: 15).call(dealership:, service_type:, date:) }

  before do
    create(:dealership_opening_hour, dealership:)
    create(:technician_qualification, technician: tech, qualification:)
    create(:technician_shift, technician: tech)
  end

  def starts(list = slots)
    list.map(&:starts_at)
  end

  def book(bay:, technician:, from:, to:)
    create(:appointment, dealership:, service_bay: bay, technician:, start_at: from, end_at: to)
  end

  it "AC8 returns every grid start that leaves a full service inside opening hours" do
    expect(slots.size).to eq(33)
    expect(starts.first).to eq(Time.utc(2030, 1, 7, 8))
    expect(starts.last).to eq(Time.utc(2030, 1, 7, 16))
    expect(slots.map(&:duration).uniq).to eq([ 3600.0 ])
    expect(starts).to eq(starts.sort)
  end

  it "AC8 removes starts that overlap a booked bay" do
    book(bay:, technician: create(:technician, dealership:), from: Time.utc(2030, 1, 7, 9), to: Time.utc(2030, 1, 7, 10))

    expect(slots.size).to eq(26)
    expect(starts).to include(Time.utc(2030, 1, 7, 8), Time.utc(2030, 1, 7, 10))
    expect(starts).not_to include(Time.utc(2030, 1, 7, 8, 15), Time.utc(2030, 1, 7, 9, 45))
    expect(starts.index(Time.utc(2030, 1, 7, 10))).to eq(starts.index(Time.utc(2030, 1, 7, 8)) + 1)
  end

  context "AC9 agreement with the SQL queries" do
    let!(:bay_two) { create(:service_bay, dealership:) }
    let!(:tech_two) { create(:technician, dealership:) }

    before do
      create(:technician_qualification, technician: tech_two, qualification:)
      create(:technician_shift, technician: tech_two, starts_at: "08:00", ends_at: "12:00")
      create(:technician_shift, technician: tech_two, starts_at: "13:00", ends_at: "17:00")
      create(:technician_time_off, technician: tech, start_at: Time.utc(2030, 1, 7, 11), end_at: Time.utc(2030, 1, 7, 12, 30))
      create(:bay_block, service_bay: bay_two, start_at: Time.utc(2030, 1, 7, 8), end_at: Time.utc(2030, 1, 7, 10))
      book(bay:, technician: tech_two, from: Time.utc(2030, 1, 7, 9), to: Time.utc(2030, 1, 7, 10))
      book(bay:, technician: tech, from: Time.utc(2030, 1, 7, 14), to: Time.utc(2030, 1, 7, 15, 30))
    end

    it "keeps a start iff both FreeBays and FreeTechnicians are non-empty" do
      kept = starts
      expected = (0..32).map { |i| Time.utc(2030, 1, 7, 8) + i * 900 }.select do |start|
        interval = Scheduling::TimeInterval.new(starts_at: start, ends_at: start + 3600)
        Availability::FreeBays.new(dealership:, service_type:, interval:).call.exists? &&
          Availability::FreeTechnicians.new(dealership:, service_type:, interval:).call.exists?
      end

      expect(kept).to eq(expected)
      expect(kept).not_to be_empty
      expect(kept.size).to be < 33
    end
  end

  context "EC4 closed days, past starts and other zones" do
    it "returns no slots on a holiday" do
      create(:dealership_holiday, dealership:, holiday_on: date)
      expect(slots).to eq([])
    end

    it "returns no slots on a day without opening hours" do
      expect(described_class.new(clock:, slot_minutes: 15).call(dealership:, service_type:, date: Date.new(2030, 1, 6))).to eq([])
    end

    it "excludes starts at or before the clock" do
      allow(clock).to receive(:now).and_return(Time.utc(2030, 1, 7, 10))
      expect(starts.first).to eq(Time.utc(2030, 1, 7, 10, 15))
    end

    it "uses the dealership time zone" do
      ny = create(:dealership, time_zone: "America/New_York")
      create(:dealership_opening_hour, dealership: ny, opens_at: "09:00", closes_at: "17:00")
      create(:service_bay, dealership: ny)
      ny_tech = create(:technician, dealership: ny)
      create(:technician_qualification, technician: ny_tech, qualification:)
      create(:technician_shift, technician: ny_tech, starts_at: "09:00", ends_at: "17:00")

      result = described_class.new(clock:, slot_minutes: 15).call(dealership: ny, service_type:, date:)
      expect(starts(result).first).to eq(Time.utc(2030, 1, 7, 14))
    end
  end

  context "EC5 bulk loading" do
    def query_count
      count = 0
      counter = ->(*, payload) { count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name]) || payload[:cached] }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { described_class.new(clock:, slot_minutes: 15).call(dealership:, service_type:, date:) }
      count
    end

    it "runs at most 8 queries with or without appointments" do
      query_count
      baseline = query_count
      10.times do |i|
        other = create(:technician, dealership:)
        book(bay: create(:service_bay, dealership:), technician: other, from: Time.utc(2030, 1, 7, 8) + i * 900, to: Time.utc(2030, 1, 7, 8, 15) + i * 900)
      end

      expect(baseline).to be <= 8
      expect(query_count).to be <= 8
      expect(query_count).to eq(baseline)
    end
  end
end
