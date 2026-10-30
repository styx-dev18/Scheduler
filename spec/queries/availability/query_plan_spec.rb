require "rails_helper"

RSpec.describe "Availability query plans" do
  let(:dealership) { create(:dealership) }
  let(:qualification) { create(:qualification) }
  let(:service_type) { create(:service_type, required_qualification: qualification) }
  let(:interval) { Scheduling::TimeInterval.new(starts_at: Time.utc(2030, 1, 7, 9), ends_at: Time.utc(2030, 1, 7, 10)) }

  before do
    bay = create(:service_bay, dealership:)
    technician = create(:technician, dealership:)
    create(:technician_qualification, technician:, qualification:)
    create(:technician_shift, technician:)
    create(:appointment, dealership:, service_bay: bay, technician:, start_at: Time.utc(2030, 1, 7, 12), end_at: Time.utc(2030, 1, 7, 13))
    ActiveRecord::Base.connection.execute("SET LOCAL enable_seqscan = off")
  end

  {
    "FreeBays" => Availability::FreeBays,
    "FreeTechnicians" => Availability::FreeTechnicians
  }.each do |label, query|
    it "AC15 #{label} uses a GiST index on time_range instead of a sequential scan on appointments" do
      plan = query.new(dealership:, service_type:, interval:).call.explain(:analyze).pluck(:id)

      expect(plan).not_to include("Seq Scan on appointments")
      expect(plan).to match(/using (index_appointments_on_\w+_time_range|appointments_no_\w+_overlap)/)
    end
  end
end
