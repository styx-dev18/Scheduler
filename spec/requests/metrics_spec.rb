require "rails_helper"

RSpec.describe "Metrics" do
  let(:dealership) { create(:dealership) }
  let(:qualification) { create(:qualification) }
  let(:service_type) { create(:service_type, required_qualification: qualification) }
  let(:customer) { create(:customer) }
  let(:vehicle) { create(:vehicle, customer:) }
  let!(:bay) { create(:service_bay, dealership:) }
  let!(:tech) { create(:technician, dealership:) }
  let(:payload) do
    {
      customer_id: customer.id, vehicle_id: vehicle.id, service_type_id: service_type.id,
      dealership_id: dealership.id, start_at: "2030-01-07T09:00:00Z"
    }
  end

  before do
    travel_to Time.utc(2030, 1, 1)
    create(:dealership_opening_hour, dealership:)
    create(:technician_qualification, technician: tech, qualification:)
    create(:technician_shift, technician: tech)
  end

  def seen_duration_count
    scrape_metrics[/^booking_duration_seconds(?:_seconds)?_count\s+(\S+)$/, 1].to_f
  end

  def seen_availability_count
    scrape_metrics[/^availability_query_duration_seconds(?:_seconds)?_count\s+(\S+)$/, 1].to_f
  end

  def competing_payload
    rival = create(:customer)
    payload.merge(customer_id: rival.id, vehicle_id: create(:vehicle, customer: rival).id)
  end

  describe "booking" do
    it "AC1 counts a successful booking as an attempt and a success and observes its duration" do
      attempts = metric_sample("booking_attempts_total")
      successes = metric_sample("booking_success_total")
      failures = scrape_metrics.scan(/^booking_failure_total.*$/)
      durations = seen_duration_count

      post "/api/v1/appointments", params: payload

      expect(response).to have_http_status(:created)
      aggregate_failures do
        expect(metric_sample("booking_attempts_total")).to eq(attempts + 1)
        expect(metric_sample("booking_success_total")).to eq(successes + 1)
        expect(seen_duration_count).to eq(durations + 1)
        expect(scrape_metrics.scan(/^booking_failure_total.*$/)).to eq(failures)
      end
    end

    it "AC2 counts a conflict as a failure labelled with its code and not as a success" do
      post "/api/v1/appointments", params: payload
      expect(response).to have_http_status(:created)
      attempts = metric_sample("booking_attempts_total")
      successes = metric_sample("booking_success_total")
      durations = seen_duration_count

      post "/api/v1/appointments", params: competing_payload

      code = response.parsed_body.dig("error", "code")
      expect(response).to have_http_status(:conflict)
      aggregate_failures do
        expect(metric_sample("booking_failure_total", %({reason="#{code}"}))).to be >= 1
        expect(metric_sample("booking_attempts_total")).to eq(attempts + 1)
        expect(metric_sample("booking_success_total")).to eq(successes)
        expect(seen_duration_count).to eq(durations + 1)
      end
    end

    it "AC2 increments the failure counter by exactly one for a validation failure" do
      before_count = metric_sample("booking_failure_total", %({reason="VALIDATION_ERROR"}))

      post "/api/v1/appointments", params: payload.except(:vehicle_id)

      expect(response).to have_http_status(:bad_request)
      expect(metric_sample("booking_failure_total", %({reason="VALIDATION_ERROR"}))).to eq(before_count + 1)
    end

    it "AC3 reports a failure from the booking service notification without a success" do
      failures = metric_sample("booking_failure_total", %({reason="NO_BAY"}))
      successes = metric_sample("booking_success_total")

      ActiveSupport::Notifications.instrument("booking.scheduler") { |event_payload| event_payload[:failure_code] = "NO_BAY" }

      aggregate_failures do
        expect(metric_sample("booking_failure_total", %({reason="NO_BAY"}))).to eq(failures + 1)
        expect(metric_sample("booking_success_total")).to eq(successes)
      end
    end
  end

  describe "availability" do
    it "AC4 observes the availability query duration" do
      observed = seen_availability_count

      get "/api/v1/availability",
          params: { dealership_id: dealership.id, service_type_id: service_type.id, date: "2030-01-07" }

      expect(response).to have_http_status(:ok)
      expect(seen_availability_count).to eq(observed + 1)
    end

    it "AC4 does not observe a duration for an invalid availability request" do
      observed = seen_availability_count

      get "/api/v1/availability", params: { dealership_id: "nope" }

      expect(response).to have_http_status(:bad_request)
      expect(seen_availability_count).to eq(observed)
    end
  end

  describe "labels" do
    it "AC5 exposes no identifier-like labels or values after bookings and queries" do
      post "/api/v1/appointments", params: payload
      post "/api/v1/appointments", params: competing_payload
      get "/api/v1/availability",
          params: { dealership_id: dealership.id, service_type_id: service_type.id, date: "2030-01-07" }

      text = scrape_metrics
      label_names = text.scan(/(\w+)="/).flatten.uniq - %w[le]

      aggregate_failures do
        expect(label_names - %w[reason]).to all(satisfy { |name| !name.end_with?("id") })
        expect(text).not_to match(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/)
        expect(text).not_to include(customer.id, vehicle.id, dealership.id, service_type.id)
      end
    end
  end

  describe "Current.appointment_id" do
    def capture_current_appointment_id
      seen = nil
      callback = ->(*) { seen = Current.appointment_id }
      ActiveSupport::Notifications.subscribed(callback, "process_action.action_controller") { yield }
      seen
    end

    it "AC6 is set to the new appointment id by create" do
      seen = capture_current_appointment_id { post "/api/v1/appointments", params: payload }

      expect(seen).to eq(response.parsed_body.dig("data", "id"))
    end

    it "AC6 is set to the appointment id by show" do
      appointment = create(:appointment)

      seen = capture_current_appointment_id { get "/api/v1/appointments/#{appointment.id}" }

      expect(seen).to eq(appointment.id)
    end

    it "AC6 stays unset when create fails" do
      seen = capture_current_appointment_id { post "/api/v1/appointments", params: payload.except(:vehicle_id) }

      expect(seen).to be_nil
    end
  end

  describe "GET /metrics" do
    around do |example|
      saved = ENV.to_h.slice("METRICS_ENABLED", "METRICS_TOKEN")
      begin
        example.run
      ensure
        ENV.delete("METRICS_ENABLED")
        ENV.delete("METRICS_TOKEN")
        saved.each { |key, value| ENV[key] = value }
        Rails.application.reload_routes!
      end
    end

    def enable_metrics(token: nil)
      ENV["METRICS_ENABLED"] = "true"
      token ? ENV["METRICS_TOKEN"] = token : ENV.delete("METRICS_TOKEN")
      Rails.application.reload_routes!
    end

    context "when METRICS_ENABLED is not true" do
      it "AC7 does not mount the route" do
        ENV["METRICS_ENABLED"] = "false"
        Rails.application.reload_routes!

        get "/metrics"

        expect(response).to have_http_status(:not_found)
      end
    end

    context "when enabled without a token" do
      before { enable_metrics }

      it "AC7 serves Prometheus text with the booking and availability metrics" do
        post "/api/v1/appointments", params: payload

        get "/metrics"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(
          "# TYPE booking_attempts_total counter", "# TYPE booking_success_total counter",
          "# TYPE booking_failure_total counter", "# TYPE booking_duration_seconds histogram",
          "# TYPE availability_query_duration_seconds histogram"
        )
      end
    end

    context "when a token is set" do
      before { enable_metrics(token: "metrics-secret-token") }

      it "AC8 serves metrics for the matching bearer token" do
        get "/metrics", headers: { "Authorization" => "Bearer metrics-secret-token" }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("booking_attempts_total")
      end

      it "AC8 rejects a wrong token with 401 UNAUTHORIZED" do
        get "/metrics", headers: { "Authorization" => "Bearer wrong-token" }

        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body).to include("success" => false, "data" => nil)
        expect(response.parsed_body["error"]).to include("code" => "UNAUTHORIZED", "status" => 401)
      end

      it "AC8 rejects a missing token with 401 UNAUTHORIZED" do
        get "/metrics"

        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body.dig("error", "code")).to eq("UNAUTHORIZED")
      end
    end
  end
end
