# frozen_string_literal: true

FactoryBot.define do
  factory :rate_card_applied_tax, class: "RateCard::AppliedTax" do
    rate_card
    tax { association(:tax, organization: rate_card.organization) }
    organization { rate_card.organization }
  end
end
