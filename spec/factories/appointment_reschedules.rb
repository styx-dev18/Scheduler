FactoryBot.define do
  factory :appointment_reschedule do
    association :appointment
    prev_start_at { Time.utc(2030, 1, 7, 9) }
    prev_end_at { Time.utc(2030, 1, 7, 10) }
    new_start_at { Time.utc(2030, 1, 7, 9, 15) }
    new_end_at { Time.utc(2030, 1, 7, 10, 15) }
    actor { "customer" }
  end
end
