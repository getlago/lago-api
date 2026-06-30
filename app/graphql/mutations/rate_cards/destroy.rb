# frozen_string_literal: true

module Mutations
  module RateCards
    class Destroy < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "rate_cards:delete"

      graphql_name "DestroyRateCard"
      description "Deletes a rate card"

      argument :id, ID, required: true

      field :id, ID, null: true

      def resolve(id:)
        rate_card = current_organization.rate_cards.find_by(id:)
        result = ::RateCards::DestroyService.call(rate_card:)

        result.success? ? result.rate_card : result_error(result)
      end
    end
  end
end
