# frozen_string_literal: true

module Mutations
  module RateCards
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "rate_cards:create"

      graphql_name "CreateRateCard"
      description "Creates a new rate card"

      input_object_class Types::RateCards::CreateInput
      type Types::RateCards::Object

      def resolve(**args)
        product_item = current_organization.product_items.find_by(id: args[:product_item_id])

        params = args.except(:product_item_id)
        params[:rates] = params[:rates].map(&:to_h) if params[:rates]

        result = ::RateCards::CreateService.call(product_item:, params:)

        result.success? ? result.rate_card : result_error(result)
      end
    end
  end
end
