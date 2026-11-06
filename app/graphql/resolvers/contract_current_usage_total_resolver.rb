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

      result = ::Contracts::CurrentUsageService.call(contract:, apply_taxes: true)
      return totals(result, taxes_unavailable: false) if result.success?
      return result_error(result) unless provider_failure?(result)

      # The provider being down shouldn't hide the summary line entirely - fall back to the
      # untaxed total rather than failing the whole query, but flag it so the client can tell
      # this isn't a genuine zero-tax result.
      fallback = ::Contracts::CurrentUsageService.call(contract:, apply_taxes: false)
      return result_error(fallback) unless fallback.success?

      totals(fallback, taxes_unavailable: true)
    end

    private

    def provider_failure?(result)
      result.error.is_a?(BaseService::ThirdPartyFailure) || result.error.is_a?(BaseService::TooManyProviderRequestsFailure)
    end

    def totals(result, taxes_unavailable:)
      billing_segments = result.rate_card_usages.map(&:billing_segment)

      Totals.new(
        amount_cents: result.amount_cents, taxes_amount_cents: result.taxes_amount_cents,
        total_amount_cents: result.total_amount_cents, taxes_unavailable:,
        from_datetime: billing_segments.map(&:started_at).min,
        to_datetime: billing_segments.map(&:ended_at).max
      )
    end
  end
end
