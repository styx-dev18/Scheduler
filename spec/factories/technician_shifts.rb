FactoryBot.define do
  factory :technician_shift do
    technician
    day_of_week { 1 }
    starts_at { "08:00" }
    ends_at { "17:00" }
  end
end
