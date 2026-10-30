FactoryBot.define do
  factory :bay_block do
    service_bay
    start_at { Time.utc(2030, 1, 7, 8) }
    end_at { Time.utc(2030, 1, 7, 12) }
  end
end
