FactoryBot.define do
  factory :technician_time_off do
    technician
    start_at { Time.utc(2030, 1, 7, 8) }
    end_at { Time.utc(2030, 1, 7, 12) }
  end
end
