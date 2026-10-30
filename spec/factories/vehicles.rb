FactoryBot.define do
  factory :vehicle do
    customer
    sequence(:vin) { |n| "VIN#{n.to_s.rjust(14, '0')}" }
    make { "Toyota" }
    model { "Corolla" }
  end
end
