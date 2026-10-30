require "rails_helper"

RSpec.describe "GET /health" do
  let(:ok_envelope) do
    { "success" => true, "data" => { "status" => "ok" }, "error" => nil, "message" => nil }
  end

  it "AC1 returns 200 in the envelope" do
    get "/health"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(ok_envelope)
  end

  it "AC1 serves the same envelope on /health/live" do
    get "/health/live"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(ok_envelope)
  end

  describe "GET /health/ready" do
    it "AC1 returns 200 when the database is reachable and migrations are applied" do
      get "/health/ready"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(ok_envelope)
    end

    it "EC1 returns 503 SERVICE_UNAVAILABLE when the database check raises" do
      allow(ActiveRecord::Base.connection_pool).to receive(:migration_context)
        .and_raise(ActiveRecord::ConnectionNotEstablished)

      get "/health/ready"

      expect(response).to have_http_status(:service_unavailable)
      body = response.parsed_body
      expect([ body["success"], body["data"], body.dig("error", "code") ]).to eq([ false, nil, "SERVICE_UNAVAILABLE" ])
    end

    it "EC2 returns 503 SERVICE_UNAVAILABLE when migrations are pending" do
      migration_context = instance_double(ActiveRecord::MigrationContext, needs_migration?: true)
      allow(ActiveRecord::Base.connection_pool).to receive(:migration_context).and_return(migration_context)

      get "/health/ready"

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body.dig("error", "code")).to eq("SERVICE_UNAVAILABLE")
    end
  end
end
