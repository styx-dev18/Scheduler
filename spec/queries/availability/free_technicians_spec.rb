require "rails_helper"

RSpec.describe Availability::FreeTechnicians do
  let(:dealership) { create(:dealership) }
  let(:qualification) { create(:qualification) }
  let(:service_type) { create(:service_type, required_qualification: qualification) }
  let(:interval) { Scheduling::TimeInterval.new(starts_at: Time.utc(2030, 1, 7, 9), ends_at: Time.utc(2030, 1, 7, 10)) }
  let!(:tech) { create(:technician, dealership:) }

  subject(:ids) { described_class.new(dealership:, service_type:, interval:).call.pluck(:id) }

  def qualify(technician)
    create(:technician_qualification, technician:, qualification:)
  end

  def shift(technician, starts_at: "08:00", ends_at: "17:00", day_of_week: 1)
    create(:technician_shift, technician:, starts_at:, ends_at:, day_of_week:)
  end

  before do
    qualify(tech)
    shift(tech)
  end

  it "AC4 returns a qualified technician on shift" do
    expect(ids).to eq([ tech.id ])
  end

  it "AC4 also returns unqualified technicians when no qualification is required" do
    other = create(:technician, dealership:)
    shift(other)
    open_type = create(:service_type)
    result = described_class.new(dealership:, service_type: open_type, interval:).call.pluck(:id)
    expect(result).to match_array([ tech.id, other.id ])
  end

  context "EC3 exclusions" do
    let!(:ec3) { create(:technician, dealership:) }

    before do
      qualify(ec3)
      shift(ec3)
    end

    it "excludes an unqualified technician" do
      ec3.technician_qualifications.destroy_all
      expect(ids).not_to include(ec3.id)
    end

    it "excludes a technician without a Monday shift" do
      ec3.technician_shifts.destroy_all
      shift(ec3, day_of_week: 2)
      expect(ids).not_to include(ec3.id)
    end

    it "excludes a technician whose shift starts after the interval start" do
      ec3.technician_shifts.destroy_all
      shift(ec3, starts_at: "09:30", ends_at: "17:00")
      expect(ids).not_to include(ec3.id)
    end

    it "excludes a technician on time off" do
      create(:technician_time_off, technician: ec3, start_at: Time.utc(2030, 1, 7, 9, 30), end_at: Time.utc(2030, 1, 7, 11))
      expect(ids).not_to include(ec3.id)
    end

    it "excludes a technician with an active appointment" do
      create(:appointment, dealership:, technician: ec3, start_at: Time.utc(2030, 1, 7, 9, 45), end_at: Time.utc(2030, 1, 7, 10, 45))
      expect(ids).not_to include(ec3.id)
    end

    it "excludes a technician whose interval spans two shifts" do
      ec3.technician_shifts.destroy_all
      shift(ec3, starts_at: "08:00", ends_at: "09:30")
      shift(ec3, starts_at: "09:30", ends_at: "12:00")
      expect(ids).not_to include(ec3.id)
    end

    it "excludes an inactive technician" do
      ec3.update!(active: false)
      expect(ids).not_to include(ec3.id)
    end
  end

  it "ignores cancelled appointments" do
    create(:appointment, :cancelled, dealership:, technician: tech, start_at: Time.utc(2030, 1, 7, 9), end_at: Time.utc(2030, 1, 7, 10))
    expect(ids).to eq([ tech.id ])
  end

  context "AC4 dedicated scenarios" do
    let!(:ec4) { create(:technician, dealership:) }

    before do
      qualify(ec4)
      ec4.technician_shifts.destroy_all
    end

    it "excludes a technician whose shift ends before the interval ends" do
      shift(ec4, starts_at: "08:00", ends_at: "09:30")
      expect(ids).not_to include(ec4.id)
    end

    it "includes a technician whose time off starts when the interval ends" do
      shift(ec4)
      create(:technician_time_off, technician: ec4, start_at: Time.utc(2030, 1, 7, 10), end_at: Time.utc(2030, 1, 7, 11))
      expect(ids).to include(ec4.id)
    end

    it "returns nothing for an interval crossing midnight" do
      shift(ec4, starts_at: "00:00", ends_at: "23:59")
      crossing = Scheduling::TimeInterval.new(starts_at: Time.utc(2030, 1, 7, 23, 30), ends_at: Time.utc(2030, 1, 8, 0, 30))
      result = described_class.new(dealership:, service_type:, interval: crossing).call.pluck(:id)
      expect(result).to eq([])
    end

    it "never returns a qualified technician of another dealership" do
      foreign = create(:technician, dealership: create(:dealership))
      qualify(foreign)
      shift(foreign)
      expect(ids).not_to include(foreign.id)
    end
  end
end
