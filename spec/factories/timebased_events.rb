FactoryBot.define do
  factory :timebased_event do
    organization { nil }
    invoice_subscription { nil }
    event_type { 1 }
    timestamp { "2024-02-21 15:01:59" }
    external_customer_id { "MyString" }
    external_subscription_id { "MyString" }
    metadata { "" }
  end
end
