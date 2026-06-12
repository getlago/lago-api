# frozen_string_literal: true

module Mutations
  module RateCardRates
    class Destroy < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "rate_cards:delete"

      graphql_name "DestroyRateCardRate"
      description "Deletes a pending rate of a rate card"

      argument :id, ID, required: true

      field :id, ID, null: true

      def resolve(id:)
        rate_card_rate = current_organization.rate_card_rates.find_by(id:)
        result = ::RateCardRates::DestroyService.call(rate_card_rate:)

        result.success? ? result.rate_card_rate : result_error(result)
      end
    end
  end
end
