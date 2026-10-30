require "rails_helper"

RSpec.describe "PATCH /api/v1/appointments/:id/status" do
  let!(:appointment) { create(:appointment) }
  let(:body) { response.parsed_body }
  let(:events) { [] }

  def patch_status(params, id: appointment.id)
    patch "/api/v1/appointments/#{id}/status", params:
  end

  def capture_events(&block)
    subscriber = ActiveSupport::Notifications.subscribe(/\Aappointment\./) { |event| events << event }
    block.call
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  it "AC8 progresses to in_progress then completed with history and events" do
    travel_to Time.utc(2030, 1, 7, 9, 5)

    capture_events do
      patch_status({ status: "in_progress" })

      expect(response).to have_http_status(:ok)
      expect(body["success"]).to be(true)
      expect(body["data"]).to include("id" => appointment.id, "status" => "in_progress")

      patch_status({ status: "completed" })

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]["status"]).to eq("completed")
    end

    aggregate_failures do
      rows = appointment.status_histories.order(:id)
      expect(rows.map { |row| [ row.from_status, row.to_status, row.changed_at, row.actor ] })
        .to match_array([
          [ "confirmed", "in_progress", Time.utc(2030, 1, 7, 9, 5), "staff" ],
          [ "in_progress", "completed", Time.utc(2030, 1, 7, 9, 5), "staff" ]
        ])
      expect(events.map(&:name)).to eq([ "appointment.status_changed" ] * 2)
      expect(events.map { |event| event.payload.values_at(:from_status, :to_status) })
        .to eq([ %w[confirmed in_progress], %w[in_progress completed] ])
    end
  end

  it "EC11 returns the allowed list for completing a confirmed appointment" do
    patch_status({ status: "completed" })

    expect(response).to have_http_status(:conflict)
    expect(body["error"]).to include("code" => "INVALID_STATUS_TRANSITION",
                                     "allowed_transitions" => %w[in_progress cancelled no_show])
    expect(appointment.reload.status).to eq("confirmed")
  end

  it "EC11 returns an empty allowed list for a completed appointment" do
    appointment.update!(status: "completed")

    patch_status({ status: "in_progress" })

    expect(response).to have_http_status(:conflict)
    expect(body["error"]).to include("code" => "INVALID_STATUS_TRANSITION", "allowed_transitions" => [])
    expect(appointment.reload.status).to eq("completed")
  end

  describe "EC12 bad status input" do
    %w[bogus cancelled].each do |status|
      it "rejects status #{status}" do
        patch_status({ status: })

        expect(response).to have_http_status(:bad_request)
        expect(body["error"]["code"]).to eq("VALIDATION_ERROR")
        expect(body["error"]["errors"]).to have_key("status")
        expect(appointment.reload.status).to eq("confirmed")
      end
    end

    it "rejects a missing status" do
      patch_status({})

      expect(response).to have_http_status(:bad_request)
      expect(body["error"]["code"]).to eq("VALIDATION_ERROR")
      expect(body["error"]["detail"]).to eq("Missing parameter: status")
    end

    it "returns 404 for an unknown appointment" do
      patch_status({ status: "in_progress" }, id: "00000000-0000-0000-0000-000000000000")

      expect(response).to have_http_status(:not_found)
      expect(body["error"]["code"]).to eq("APPOINTMENT_NOT_FOUND")
    end
  end
end
