# frozen_string_literal: true

module Mutations
  module RateCards
    class Update < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "rate_cards:update"

      graphql_name "UpdateRateCard"
      description "Updates an existing rate card"

      input_object_class Types::RateCards::UpdateInput
      type Types::RateCards::Object

      def resolve(**args)
        rate_card = current_organization.rate_cards.find_by(id: args[:id])
        result = ::RateCards::UpdateService.call(rate_card:, params: args.except(:id))

        result.success? ? result.rate_card : result_error(result)
      end
    end
  end
end
