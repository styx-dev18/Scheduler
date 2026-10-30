FactoryBot.define do
  factory :idempotency_key do
    sequence(:key) { |n| "idem-key-#{n}" }
    request_fingerprint { "fingerprint" }
  end
end
