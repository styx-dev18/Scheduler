FactoryBot.define do
  factory :appointment_status_history do
    appointment
    to_status { "confirmed" }
    changed_at { Time.utc(2030, 1, 7, 8) }
  end
end
