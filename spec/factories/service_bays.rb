FactoryBot.define do
  factory :service_bay do
    dealership
    sequence(:name) { |n| "Bay #{n}" }
    bay_type { "general" }

    trait :lift_bay do
      bay_type { "lift" }
    end
  end
end
