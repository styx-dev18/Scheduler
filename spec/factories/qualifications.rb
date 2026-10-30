FactoryBot.define do
  factory :qualification do
    sequence(:code) { |n| "QUAL_#{n}" }
    sequence(:name) { |n| "Qualification #{n}" }
  end
end
