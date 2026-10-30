require "rails_helper"

RSpec.configure do |config|
  config.openapi_root = Rails.root.join("swagger").to_s

  config.openapi_specs = {
    "v1/openapi.yaml" => {
      openapi: "3.0.3",
      info: {
        title: "Unified Service Scheduler API",
        version: "v1"
      },
      paths: {},
      servers: [ { url: "http://localhost:3000" } ],
      components: {
        schemas: {
          Envelope: {
            type: :object,
            properties: {
              success: { type: :boolean },
              data: { type: :object, nullable: true },
              error: { type: :object, nullable: true },
              message: { type: :string, nullable: true }
            },
            required: %w[success]
          },
          Error: {
            type: :object,
            properties: {
              type: { type: :string },
              title: { type: :string },
              status: { type: :integer },
              code: { type: :string },
              detail: { type: :string },
              errors: {
                type: :object,
                nullable: true,
                additionalProperties: { type: :array, items: { type: :string } },
                example: { name: [ "can't be blank" ] }
              }
            },
            required: %w[type title status code detail]
          }
        }
      }
    }
  }

  config.openapi_format = :yaml
end
