# frozen_string_literal: true

FactoryBot.define do
  factory :adjusted_fee do
    fee
    organization { fee&.organization || association(:organization) }
    invoice { fee&.invoice || association(:invoice, organization:) }
    charge { nil }
    subscription { fee&.subscription || association(:subscription, organization:) }

    fee_type { "subscription" }

    unit_amount_cents { 200 }
    units { 2 }
    adjusted_amount { true }

    invoice_display_name { Faker::Fantasy::Tolkien.character }
  end
end
