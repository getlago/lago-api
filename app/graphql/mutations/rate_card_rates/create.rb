# frozen_string_literal: true

module Mutations
  module RateCardRates
    class Create < BaseMutation
      include RequiresProductCatalog
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "rate_cards:create"

      graphql_name "CreateRateCardRate"
      description "Adds a rate to a rate card"

      input_object_class Types::RateCardRates::CreateInput
      type Types::RateCardRates::Object

      def resolve(**args)
        rate_card = current_organization.rate_cards.find_by(id: args[:rate_card_id])
        params = args.except(:rate_card_id).to_h
        # Typed input objects reach the service as plain hashes, like charges do.
        params[:rate_properties] = params[:rate_properties].to_h if params[:rate_properties]
        result = ::RateCardRates::CreateService.call(rate_card:, params:)

        result.success? ? result.rate_card_rate : result_error(result)
      end
    end
  end
end
