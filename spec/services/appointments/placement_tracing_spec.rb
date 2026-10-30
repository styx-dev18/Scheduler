require "rails_helper"

RSpec.describe Appointments::Placement, "tracing" do
  include_context "with in-memory tracing"

  let(:clock) { class_double(Clock, now: Time.utc(2030, 1, 1)) }
  let(:dealership) { create(:dealership) }
  let(:service_type) { create(:service_type) }
  let(:customer) { create(:customer) }
  let(:vehicle) { create(:vehicle, customer:) }
  let!(:bay) { create(:service_bay, dealership:) }
  let!(:technician) do
    create(:technician, dealership:).tap { |tech| create(:technician_shift, technician: tech) }
  end
  let(:placement) { described_class.new(clock:, slot_minutes: 15) }
  let(:persist) do
    lambda do |assignment, interval|
      create(:appointment, dealership:, customer:, vehicle:, service_type:, technician_id: assignment.technician_id,
                           service_bay_id: assignment.bay_id, start_at: interval.starts_at, end_at: interval.ends_at)
    end
  end
  let(:expected_attributes) { { "dealership.id" => dealership.id, "service_type.id" => service_type.id } }

  before { create(:dealership_opening_hour, dealership:) }

  def place(starts_at)
    placement.call(vehicle:, service_type:, dealership:, starts_at:, &persist)
  end

  it "AC-trace records booking.transaction with booking.assignment nested under it and the attributes" do
    result = place(Time.utc(2030, 1, 7, 9))

    transaction = finished_spans("booking.transaction").sole
    assignment = finished_spans("booking.assignment").sole
    expect(result).to be_success
    aggregate_failures do
      expect(assignment.parent_span_id).to eq(transaction.span_id)
      expect(assignment.trace_id).to eq(transaction.trace_id)
      expect(transaction.attributes).to include(expected_attributes)
      expect(assignment.attributes).to include(expected_attributes)
    end
  end

  it "AC-trace sets outcome success on the transaction and assigned on the assignment" do
    place(Time.utc(2030, 1, 7, 9))

    expect(finished_spans("booking.transaction").sole.attributes["outcome"]).to eq("success")
    expect(finished_spans("booking.assignment").sole.attributes["outcome"]).to eq("assigned")
  end

  it "AC-trace sets the transaction outcome to the lowercase failure code on a conflict" do
    create(:appointment, dealership:, service_bay: bay, technician:,
                         start_at: Time.utc(2030, 1, 7, 9), end_at: Time.utc(2030, 1, 7, 10))

    result = place(Time.utc(2030, 1, 7, 9))

    expect(result.failure.first).to eq("NO_CAPACITY")
    transaction = finished_spans("booking.transaction").sole
    aggregate_failures do
      expect(transaction.attributes["outcome"]).to eq("no_capacity")
      expect(transaction.attributes).to include(expected_attributes)
    end
  end

  it "AC-trace records no booking spans when validation fails before the transaction" do
    result = place(Time.utc(2029, 12, 31, 9))

    expect(result.failure.first).to eq("START_TIME_IN_PAST")
    expect(finished_spans("booking.transaction")).to be_empty
  end
end
