FactoryBot.define do
  factory :appointment do
    dealership
    customer
    vehicle { association :vehicle, customer: customer }
    technician { association :technician, dealership: dealership }
    service_bay { association :service_bay, dealership: dealership }
    service_type
    start_at { Time.utc(2030, 1, 7, 9) }
    end_at { Time.utc(2030, 1, 7, 10) }

    trait :cancelled do
      status { "cancelled" }
    end
  end
end
