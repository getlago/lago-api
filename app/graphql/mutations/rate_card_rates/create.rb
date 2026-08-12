# frozen_string_literal: true

module Mutations
  module RateCardRates
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "rate_cards:create"

      graphql_name "CreateRateCardRate"
      description "Adds a rate to a rate card"

      input_object_class Types::RateCardRates::CreateInput
      type Types::RateCardRates::Object

      def resolve(**args)
        rate_card = current_organization.rate_cards.find_by(id: args[:rate_card_id])
        result = ::RateCardRates::CreateService.call(rate_card:, params: args.except(:rate_card_id))

        result.success? ? result.rate_card_rate : result_error(result)
      end
    end
  end
end
