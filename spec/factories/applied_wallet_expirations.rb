# frozen_string_literal: true

FactoryBot.define do
  factory :applied_wallet_expiration do
    wallet
    invoice { association(:invoice, organization: wallet.organization, customer: wallet.customer) }
    organization { wallet.organization }
  end
end
