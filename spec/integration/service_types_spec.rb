require "swagger_helper"

RSpec.describe "GET /api/v1/service-types" do
  path "/api/v1/service-types" do
    get "List service types" do
      tags "Service types"
      produces "application/json"
      parameter name: :dealership_id, in: :query, type: :string, required: false
      parameter name: :page, in: :query, type: :integer, required: false

      let!(:dealership) { create(:dealership) }
      let!(:offered_one) { create(:service_type, name: "svc-ac8-1", description: "First") }
      let!(:offered_two) { create(:service_type, name: "svc-ac8-2") }
      let!(:not_offered) { create(:service_type, name: "svc-ac8-3") }

      before do
        create(:dealership_service_type, dealership: dealership, service_type: offered_one)
        create(:dealership_service_type, dealership: dealership, service_type: offered_two)
      end

      response "200", "AC8 all service types" do
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 data: { type: :array },
                 meta: { type: :object }
               },
               required: %w[success data meta]

        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body["data"].map { |item| item["name"] }).to eq(%w[svc-ac8-1 svc-ac8-2 svc-ac8-3])
          expect(body["data"].first.keys).to contain_exactly("id", "name", "description", "duration_minutes")
          expect(body["meta"]["total_count"]).to eq(3)
        end
      end

      response "200", "AC8 filtered by dealership" do
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 data: { type: :array },
                 meta: { type: :object }
               },
               required: %w[success data meta]

        let(:dealership_id) { dealership.id }

        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body["data"].map { |item| item["name"] }).to eq(%w[svc-ac8-1 svc-ac8-2])
          expect(body["meta"]["total_count"]).to eq(2)
        end
      end

      response "200", "EC4 unknown or malformed dealership id" do
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 data: { type: :array },
                 meta: { type: :object }
               },
               required: %w[success data meta]

        context "with an unknown UUID" do
          let(:dealership_id) { "00000000-0000-4000-8000-000000000000" }

          run_test! do |response|
            body = JSON.parse(response.body)
            expect(body["data"]).to eq([])
            expect(body["meta"]["total_count"]).to eq(0)
          end
        end

        context "with a malformed id" do
          let(:dealership_id) { "abc" }

          run_test! do |response|
            expect(JSON.parse(response.body)["data"]).to eq([])
          end
        end
      end
    end
  end
end
