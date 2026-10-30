FactoryBot.define do
  factory :service_type do
    sequence(:name) { |n| "Service #{n}" }
    duration_minutes { 60 }
    required_bay_type { "general" }
  end
end
