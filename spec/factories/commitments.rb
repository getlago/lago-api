# frozen_string_literal: true

FactoryBot.define do
  factory :commitment do
    plan
    commitment_type { 'minimum_commitment' }
    amount_cents { 1_000 }
    invoice_display_name { Faker::Subscription.plan }
  end
end
