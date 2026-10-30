FactoryBot.define do
  factory :dealership_opening_hour do
    dealership
    day_of_week { 1 }
    opens_at { "08:00" }
    closes_at { "17:00" }
  end
end
