FactoryBot.define do
  factory :dealership_holiday do
    dealership
    holiday_on { Date.new(2030, 12, 25) }
    name { "Christmas" }
  end
end
