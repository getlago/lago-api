FactoryBot.define do
  factory :data_export do
    user

    format { 'csv' }
    resource_type { "invoices" }
    resource_query { {filters: {currency: 'EUR'}} }
    status { 'pending' }
    file { nil }
    expires_at { 7.days.from_now }
    started_at { 2.hours.ago }
    completed_at { 30.minutes.ago }
  end
end
