require "rails_helper"

RSpec.describe "POST /api/v1/appointments/:id/reschedule" do
  let(:dealership) { create(:dealership) }
  let(:qualification) { create(:qualification) }
  let(:service_type) { create(:service_type, required_qualification: qualification) }
  let(:customer) { create(:customer) }
  let(:vehicle) { create(:vehicle, customer:) }
  let!(:bay) { create(:service_bay, dealership:) }
  let!(:tech) { create(:technician, dealership:) }
  let!(:appointment) do
    create(:appointment, dealership:, customer:, vehicle:, technician: tech, service_bay: bay, service_type:)
  end
  let(:body) { response.parsed_body }
  let(:events) { [] }

  before do
    travel_to Time.utc(2030, 1, 1)
    [ 1, 2 ].each do |day|
      create(:dealership_opening_hour, dealership:, day_of_week: day)
      create(:technician_shift, technician: tech, day_of_week: day)
    end
    create(:technician_qualification, technician: tech, qualification:)
  end

  def reschedule(params, id: appointment.id, headers: {})
    post "/api/v1/appointments/#{id}/reschedule", params:, headers:
  end

  def capture_events(&block)
    subscriber = ActiveSupport::Notifications.subscribe(/\Aappointment\./) { |event| events << event }
    block.call
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  it "AC4 reschedules in place, records the change, publishes the event and frees the old slot" do
    capture_events do
      reschedule({ new_start_at: "2030-01-08T11:00:00Z", lock_version: 0 }, headers: { "X-Request-Id" => "req-ac4" })
    end

    expect(response).to have_http_status(:ok)
    aggregate_failures do
      expect(body["success"]).to be(true)
      expect(body["error"]).to be_nil
      expect(body["data"]).to include("id" => appointment.id, "start_at" => "2030-01-08T11:00:00Z",
                                      "end_at" => "2030-01-08T12:00:00Z", "lock_version" => 1)
      row = appointment.reschedules.sole
      expect([ row.prev_start_at, row.prev_end_at, row.new_start_at, row.new_end_at, row.actor, row.request_id ])
        .to eq([ Time.utc(2030, 1, 7, 9), Time.utc(2030, 1, 7, 10), Time.utc(2030, 1, 8, 11),
                 Time.utc(2030, 1, 8, 12), "customer", "req-ac4" ])
      event = events.sole
      expect(event.name).to eq("appointment.rescheduled")
      expect(event.payload).to include(appointment_id: appointment.id, previous_start_at: Time.utc(2030, 1, 7, 9),
                                       request_id: "req-ac4")
    end

    other = create(:vehicle, customer:)
    post "/api/v1/appointments", params: {
      customer_id: customer.id, vehicle_id: other.id, service_type_id: service_type.id,
      dealership_id: dealership.id, start_at: "2030-01-07T09:00:00Z"
    }

    expect(response).to have_http_status(:created)
    expect(response.parsed_body["data"]).to include("service_bay_id" => bay.id, "start_at" => "2030-01-07T09:00:00Z")
  end

  describe "EC5 invalid new time" do
    def expect_unchanged
      appointment.reload
      expect([ appointment.start_at, appointment.end_at, appointment.lock_version ])
        .to eq([ Time.utc(2030, 1, 7, 9), Time.utc(2030, 1, 7, 10), 0 ])
    end

    it "rejects a missing new_start_at" do
      reschedule({})

      expect(response).to have_http_status(:bad_request)
      expect(body["error"]["code"]).to eq("VALIDATION_ERROR")
      expect(body["error"]["errors"]).to have_key("new_start_at")
      expect_unchanged
    end

    it "rejects a timestamp without an offset" do
      reschedule({ new_start_at: "2030-01-08T11:00:00" })

      expect(response).to have_http_status(:bad_request)
      expect(body["error"]["code"]).to eq("VALIDATION_ERROR")
      expect(body["error"]["errors"]).to have_key("new_start_at")
      expect_unchanged
    end

    {
      "2029-12-31T09:00:00Z" => "START_TIME_IN_PAST",
      "2030-01-08T11:10:00Z" => "START_TIME_NOT_ON_SLOT_GRID",
      "2030-01-08T22:00:00Z" => "OUTSIDE_OPENING_HOURS"
    }.each do |start, code|
      it "returns 422 #{code} for #{start}" do
        reschedule({ new_start_at: start })

        expect(response).to have_http_status(:unprocessable_content)
        expect(body["success"]).to be(false)
        expect(body["error"]["code"]).to eq(code)
        expect_unchanged
      end
    end
  end

  describe "EC6 only confirmed appointments" do
    {
      "in_progress" => [ "completed" ],
      "cancelled" => []
    }.each do |status, allowed|
      it "returns 409 for a #{status} appointment" do
        appointment.update!(status:)

        reschedule({ new_start_at: "2030-01-08T11:00:00Z" })

        expect(response).to have_http_status(:conflict)
        expect(body["error"]).to include("code" => "INVALID_STATUS_TRANSITION", "allowed_transitions" => allowed)
        appointment.reload
        expect([ appointment.status, appointment.start_at, appointment.reschedules.count ])
          .to eq([ status, Time.utc(2030, 1, 7, 9), 0 ])
      end
    end
  end

  it "EC7 returns 409 CONCURRENT_MODIFICATION for a stale lock_version" do
    appointment.update!(updated_at: Time.utc(2030, 1, 1, 1))
    expect(appointment.reload.lock_version).to eq(1)

    reschedule({ new_start_at: "2030-01-08T11:00:00Z", lock_version: 0 })

    expect(response).to have_http_status(:conflict)
    expect(body["error"]["code"]).to eq("CONCURRENT_MODIFICATION")
    expect(appointment.reload.start_at).to eq(Time.utc(2030, 1, 7, 9))
    expect(appointment.reschedules.count).to eq(0)
  end
end
