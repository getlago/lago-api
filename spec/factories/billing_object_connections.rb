# frozen_string_literal: true

FactoryBot.define do
  factory :billing_object_connection do
    owner { association(:subscription) }
    organization { owner&.organization || association(:organization) }
    category { "tax" }
    behavior { "skip" }
  end
end
