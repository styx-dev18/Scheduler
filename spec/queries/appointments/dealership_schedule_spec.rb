require "rails_helper"

RSpec.describe "Appointments dealership schedule query plan" do
  let(:dealership) { create(:dealership) }
  let(:form) { DealershipScheduleRequest.new(dealership_id: dealership.id, date: "2030-01-07") }

  before do
    create(:appointment, dealership:)
    ActiveRecord::Base.connection.execute("SET LOCAL enable_seqscan = off")
  end

  it "AC11 uses index_appointments_on_dealership_id_and_start_at for the dealership day relation" do
    relation = Appointments::ListQuery.new.call(**form.filters(dealership.time_zone))

    plan = relation.explain(:analyze).pluck(:id)

    expect(plan.to_s).to match(/Index (Only )?Scan using index_appointments_on_dealership_id_and_start_at on appointments/)
  end
end
