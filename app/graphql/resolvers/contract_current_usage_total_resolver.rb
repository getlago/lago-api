# frozen_string_literal: true

module Resolvers
  class ContractCurrentUsageTotalResolver < Resolvers::BaseResolver
    include RequiresProductCatalog
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "contracts:view"

    description "Query a contract's total computed usage for the current billing period, unfiltered"

    argument :contract_id, ID, required: true

    type Types::Contracts::CurrentUsageTotal, null: false

    Totals = Struct.new(
      :amount_cents, :taxes_amount_cents, :total_amount_cents, :taxes_unavailable,
      :from_datetime, :to_datetime, :product_category_totals, keyword_init: true
    )

    CategoryTotals = Struct.new(
      :product_category, :amount_cents, :taxes_amount_cents, :total_amount_cents,
      :from_datetime, :to_datetime, keyword_init: true
    )

    def resolve(contract_id:)
      contract = current_organization.contracts.find_by(id: contract_id)
      return not_found_error(resource: "contract") unless contract

      result = ::Contracts::CurrentUsageService.call(
        contract:, apply_taxes: true, untaxed_on_provider_failure: true, use_usage_buckets: true
      )

      if result.success?
        totals(result)
      else
        result_error(result)
      end
    end

    private

    def totals(result)
      usages = result.rate_card_usages

      Totals.new(
        amount_cents: result.amount_cents, taxes_amount_cents: result.taxes_amount_cents,
        total_amount_cents: result.total_amount_cents, taxes_unavailable: result.taxes_unavailable,
        product_category_totals: category_totals(usages),
        **window(usages)
      )
    end

    def category_totals(usages)
      by_category = usages.group_by { |usage| usage.contract_rate_card.rate_card.product.product_category }

      by_category.map do |product_category, category_usages|
        amount_cents = category_usages.sum(&:amount_cents)
        taxes_amount_cents = category_usages.sum(&:taxes_amount_cents)

        CategoryTotals.new(
          product_category:, amount_cents:, taxes_amount_cents:,
          total_amount_cents: amount_cents + taxes_amount_cents,
          **window(category_usages)
        )
      end
    end

    def window(usages)
      billing_segments = usages.map(&:billing_segment)

      {from_datetime: billing_segments.map(&:started_at).min, to_datetime: billing_segments.map(&:ended_at).max}
    end
  end
end
