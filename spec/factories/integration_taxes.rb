# frozen_string_literal: true

FactoryBot.define do
  factory :tax_result, class: "Integrations::Aggregator::Taxes::TaxResult" do
    skip_create
    initialize_with do
      new(item_key:, item_id:, item_code:, amount_cents:, tax_amount_cents:, tax_breakdown:)
    end

    item_key { nil }
    item_id { nil }
    item_code { nil }
    amount_cents { nil }
    tax_amount_cents { nil }
    tax_breakdown { [] }
  end

  factory :tax_breakdown_item, class: "Integrations::Aggregator::Taxes::TaxResult::TaxBreakdownItem" do
    skip_create
    initialize_with { new(name:, rate:, tax_amount:, type:) }

    name { nil }
    rate { nil }
    tax_amount { nil }
    type { nil }
  end
end
