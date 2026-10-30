FactoryBot.define do
  factory :technician do
    dealership
    sequence(:name) { |n| "Technician #{n}" }
  end
end
