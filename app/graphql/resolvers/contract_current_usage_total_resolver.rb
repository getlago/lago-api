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
      :from_datetime, :to_datetime, keyword_init: true
    )

    def resolve(contract_id:)
      contract = current_organization.contracts.find_by(id: contract_id)
      return not_found_error(resource: "contract") unless contract

      result = ::Contracts::CurrentUsageService.call(contract:, apply_taxes: true, untaxed_on_provider_failure: true)

      if result.success?
        totals(result)
      else
        result_error(result)
      end
    end

    private

    def totals(result)
      billing_segments = result.rate_card_usages.map(&:billing_segment)

      Totals.new(
        amount_cents: result.amount_cents, taxes_amount_cents: result.taxes_amount_cents,
        total_amount_cents: result.total_amount_cents, taxes_unavailable: result.taxes_unavailable,
        from_datetime: billing_segments.map(&:started_at).min,
        to_datetime: billing_segments.map(&:ended_at).max
      )
    end
  end
end
