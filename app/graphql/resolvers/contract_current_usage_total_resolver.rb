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

    def resolve(contract_id:)
      contract = current_organization.contracts.find_by(id: contract_id)
      return not_found_error(resource: "contract") unless contract

      result = ::Contracts::CurrentUsageService.call(contract:, apply_taxes: true)
      return result if result.success?
      return result_error(result) unless provider_failure?(result)

      # The provider being down shouldn't hide the summary line entirely - fall back to the
      # untaxed total rather than failing the whole query.
      fallback = ::Contracts::CurrentUsageService.call(contract:, apply_taxes: false)
      return result_error(fallback) unless fallback.success?

      fallback
    end

    private

    def provider_failure?(result)
      result.error.is_a?(BaseService::ThirdPartyFailure) || result.error.is_a?(BaseService::TooManyProviderRequestsFailure)
    end
  end
end
