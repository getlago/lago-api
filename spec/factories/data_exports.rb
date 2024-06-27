FactoryBot.define do
  factory :data_export do
    user

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
      expires_at { 7.days.from_now }
      completed_at { 30.minutes.ago }
    end

    trait :failed do
      status { 'failed' }
    end
  end
end
