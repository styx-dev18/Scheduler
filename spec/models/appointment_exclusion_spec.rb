require "rails_helper"

RSpec.describe Appointment, "exclusion constraints" do
  let!(:existing) { create(:appointment) }

  def insert_overlap(**overrides)
    attrs = {
      dealership: existing.dealership, customer: existing.customer, service_type: existing.service_type,
      vehicle: create(:vehicle, customer: existing.customer),
      technician: create(:technician, dealership: existing.dealership),
      service_bay: create(:service_bay, dealership: existing.dealership)
    }.merge(overrides)
    described_class.transaction(requires_new: true) { create(:appointment, **attrs) }
  end

  it "rejects an overlapping appointment on the same bay" do
    expect { insert_overlap(service_bay: existing.service_bay) }
      .to raise_error(ActiveRecord::StatementInvalid) { |e| expect(e.cause).to be_a(PG::ExclusionViolation) }
  end

  it "rejects an overlapping appointment on the same technician" do
    expect { insert_overlap(technician: existing.technician) }
      .to raise_error(ActiveRecord::StatementInvalid) { |e| expect(e.cause).to be_a(PG::ExclusionViolation) }
  end

  it "rejects an overlapping appointment on the same vehicle" do
    expect { insert_overlap(vehicle: existing.vehicle) }
      .to raise_error(ActiveRecord::StatementInvalid) { |e| expect(e.cause).to be_a(PG::ExclusionViolation) }
  end

  it "allows back-to-back appointments on the same resources" do
    expect do
      insert_overlap(vehicle: existing.vehicle, technician: existing.technician, service_bay: existing.service_bay,
                     start_at: existing.end_at, end_at: existing.end_at + 1.hour)
    end.not_to raise_error
  end

  it "allows an overlapping appointment when the existing one is cancelled" do
    existing.update!(status: "cancelled")

    expect do
      insert_overlap(vehicle: existing.vehicle, technician: existing.technician, service_bay: existing.service_bay)
    end.not_to raise_error
  end
end
