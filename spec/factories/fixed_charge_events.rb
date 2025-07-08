FactoryBot.define do
  factory :fixed_charge_event do
    organization { nil }
    customer { nil }
    code { "MyString" }
    properties { "" }
    timestamp { "2025-07-08 15:52:15" }
    subscription { nil }
    deleted_at { "2025-07-08 15:52:15" }
  end
end
