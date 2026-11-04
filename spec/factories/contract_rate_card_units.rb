# frozen_string_literal: true

FactoryBot.define do
  factory :contract_rate_card_unit do
    organization
    contract_rate_card { association(:contract_rate_card, organization:) }
    units { 1 }
    effective_date { contract_rate_card.effective_date }
  end
end
