# frozen_string_literal: true

FactoryBot.define do
  factory :contract_rate_card do
    organization
    contract { association(:contract, organization:) }
    rate_card { association(:rate_card, organization:) }
    billing_anchor_date { Date.current }
    effective_date { Date.current }
    transient do
      units { nil }
    end

    after(:build) do |contract_rate_card, evaluator|
      if evaluator.units.present?
        contract_rate_card.terms.build(
          organization: contract_rate_card.organization,
          units: evaluator.units,
          effective_date: contract_rate_card.effective_date
        )
      end
    end
  end
end
