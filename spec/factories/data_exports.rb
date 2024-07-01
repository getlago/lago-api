FactoryBot.define do
  factory :data_export do
    organization
    membership { association :membership, organization: organization }

    format { 'csv' }
    resource_type { "invoices" }
    resource_query { {filters: {currency: 'EUR'}} }
    status { 'pending' }
    file { nil }

    trait :processing do
      status { 'processing' }
      started_at { 2.hours.ago }
    end

    trait :completed do
      status { 'completed' }
      started_at { 2.hours.ago }
      completed_at { 30.minutes.ago }
      expires_at { 7.days.from_now }
    end

    trait :expired do
      completed
      expires_at { 1.day.ago }
    end
  end
end
