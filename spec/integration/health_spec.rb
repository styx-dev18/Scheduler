require "swagger_helper"

RSpec.describe "GET /health" do
  path "/health" do
    get "Health check" do
      tags "Health"
      produces "application/json"

      response "200", "AC10 service is healthy" do
        schema "$ref" => "#/components/schemas/Envelope"

        run_test! do |response|
          expect(JSON.parse(response.body)["data"]).to eq("status" => "ok")
        end
      end
    end
  end

  path "/health/live" do
    get "Liveness check" do
      tags "Health"
      produces "application/json"

      response "200", "AC10 process is alive" do
        schema "$ref" => "#/components/schemas/Envelope"

        run_test! do |response|
          expect(JSON.parse(response.body)["data"]).to eq("status" => "ok")
        end
      end
    end
  end

  path "/health/ready" do
    get "Readiness check" do
      tags "Health"
      produces "application/json"

      response "200", "AC10 database is reachable and migrations are applied" do
        schema "$ref" => "#/components/schemas/Envelope"

        run_test! do |response|
          expect(JSON.parse(response.body)["data"]).to eq("status" => "ok")
        end
      end

      response "503", "EC10 database is unavailable or migrations are pending" do
        schema "$ref" => "#/components/schemas/Envelope"

        before do
          allow(ActiveRecord::Base.connection_pool).to receive(:migration_context)
            .and_raise(ActiveRecord::ConnectionNotEstablished)
        end

        run_test! do |response|
          expect(JSON.parse(response.body).dig("error", "code")).to eq("SERVICE_UNAVAILABLE")
        end
      end
    end
  end
end
