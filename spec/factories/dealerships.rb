FactoryBot.define do
  factory :dealership do
    sequence(:name) { |n| "Dealership #{n}" }
    time_zone { "Europe/London" }
  end
end
