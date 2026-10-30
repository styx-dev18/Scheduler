require "swagger_helper"

RSpec.describe "GET /api/v1/dealerships" do
  path "/api/v1/dealerships" do
    get "List dealerships" do
      tags "Dealerships"
      produces "application/json"
      parameter name: :page, in: :query, type: :integer, required: false

      response "200", "AC7 dealerships with opening hours" do
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 data: { type: :array },
                 meta: { type: :object }
               },
               required: %w[success data meta]

        before do
          create_list(:dealership, 3).each do |dealership|
            (1..5).each { |day| create(:dealership_opening_hour, dealership: dealership, day_of_week: day) }
          end
        end

        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body["success"]).to be(true)
          expect(body["data"].size).to eq(3)
          expect(body["data"].first.keys).to contain_exactly("id", "name", "time_zone", "opening_hours")
          expect(body["data"].first["opening_hours"].first).to eq(
            "day_of_week" => 1, "opens_at" => "08:00", "closes_at" => "17:00"
          )
          expect(body["meta"]).to eq("page" => 1, "per_page" => 25, "total_pages" => 1, "total_count" => 3)
        end
      end

      response "400", "EC4 invalid page" do
        schema "$ref" => "#/components/schemas/Envelope"

        context "with page 0" do
          let(:page) { 0 }

          run_test! do |response|
            body = JSON.parse(response.body)
            expect(body["error"]["code"]).to eq("VALIDATION_ERROR")
            expect(body["error"]["errors"]).to have_key("page")
          end
        end

        context "with a non-numeric page" do
          let(:page) { "abc" }

          run_test! do |response|
            expect(JSON.parse(response.body)["error"]["errors"]).to have_key("page")
          end
        end

        context "with a page past the last" do
          let(:page) { 99 }

          before { create(:dealership) }

          run_test! do |response|
            expect(JSON.parse(response.body)["error"]["errors"]).to have_key("page")
          end
        end
      end
    end
  end
end
