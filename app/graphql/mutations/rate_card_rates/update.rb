# frozen_string_literal: true

module Mutations
  module RateCardRates
    class Update < BaseMutation
      include RequiresProductCatalog
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "rate_cards:update"

      graphql_name "UpdateRateCardRate"
      description "Updates a rate of a rate card"

      input_object_class Types::RateCardRates::UpdateInput
      type Types::RateCardRates::Object

      def resolve(**args)
        rate_card_rate = current_organization.rate_card_rates.find_by(id: args[:id])
        params = args.except(:id).to_h
        # Typed input objects reach the service as plain hashes, like charges do.
        params[:rate_properties] = params[:rate_properties].to_h if params[:rate_properties]
        result = ::RateCardRates::UpdateService.call(rate_card_rate:, params:)

        result.success? ? result.rate_card_rate : result_error(result)
      end
    end
  end
end
