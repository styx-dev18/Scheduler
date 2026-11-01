require "rails_helper"

RSpec.describe "Availability tracing" do
  include_context "with in-memory tracing"

  let(:dealership) { create(:dealership) }
  let(:service_type) { create(:service_type) }
  let(:interval) { Scheduling::TimeInterval.new(starts_at: Time.utc(2030, 1, 7, 9), ends_at: Time.utc(2030, 1, 7, 10)) }
  let(:expected_attributes) { { "dealership.id" => dealership.id, "service_type.id" => service_type.id } }

  it "AC19 records availability.free_bays with dealership and service type ids" do
    bay = create(:service_bay, dealership:)

    ids = Availability::FreeBays.new(dealership:, service_type:, interval:).ids

    expect(ids).to eq([ bay.id ])
    expect(finished_spans("availability.free_bays").sole.attributes).to include(expected_attributes)
  end

  it "AC19 records availability.free_technicians with dealership and service type ids" do
    technician = create(:technician, dealership:)
    create(:technician_shift, technician:)

    ids = Availability::FreeTechnicians.new(dealership:, service_type:, interval:).ids

    expect(ids).to eq([ technician.id ])
    expect(finished_spans("availability.free_technicians").sole.attributes).to include(expected_attributes)
  end

  it "AC19 runs the free_bays SQL inside the span" do
    create(:service_bay, dealership:)
    active_names = []
    callback = lambda do |*|
      span = OpenTelemetry::Trace.current_span
      active_names << span.name if span.context.valid?
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      Availability::FreeBays.new(dealership:, service_type:, interval:).ids
    end

    expect(active_names).not_to be_empty
    expect(active_names).to include("availability.free_bays")
  end

  it "EC16 does not create the span until ids is called" do
    Availability::FreeBays.new(dealership:, service_type:, interval:).call

    expect(finished_spans("availability.free_bays")).to be_empty
  end

  it "AC19 records both availability spans when the finder runs" do
    Availability::Finder.new.call(dealership:, service_type:, interval:, exclude_appointment_id: nil)

    expect(finished_spans.map(&:name)).to include("availability.free_bays", "availability.free_technicians")
  end
end
