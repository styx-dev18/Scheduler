require "rails_helper"

RSpec.describe AppointmentSerializer, "lifecycle fields" do
  def serialize(appointment)
    described_class.new(appointment).serializable_hash
  end

  it "AC15 shows lock_version 0 and null cancellation fields for a new appointment" do
    data = serialize(create(:appointment))

    expect(data).to include("lock_version" => 0, "cancelled_at" => nil, "cancellation_reason" => nil)
  end

  it "AC15 shows cancelled_at in ISO-8601 Z, reason and the bumped lock_version after cancel" do
    appointment = create(:appointment)
    appointment.cancel!(at: Time.utc(2030, 1, 1), actor: "customer", reason: "ac15")

    data = serialize(appointment.reload)

    expect(data).to include(
      "status" => "cancelled",
      "cancelled_at" => "2030-01-01T00:00:00Z",
      "cancellation_reason" => "ac15",
      "lock_version" => 1
    )
  end
end
