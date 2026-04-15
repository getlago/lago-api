# frozen_string_literal: true

module Mutations
  module Quotes
    module BillingItems
      module Coupons
        class Update < BaseMutation
          include AuthenticableApiUser
          include RequiredOrganization

          REQUIRED_PERMISSION = "quotes:update"
          graphql_name "UpdateQuoteCoupon"
          description "Updates a coupon billing item on a draft quote"

          argument :quote_id, ID, required: true
          argument :id, ID, required: true
          argument :coupon_id, ID, required: false
          argument :coupon_type, String, required: false
          argument :amount_cents, GraphQL::Types::BigInt, required: false
          argument :percentage_rate, Float, required: false
          argument :currency, String, required: false
          argument :frequency, String, required: false
          argument :frequency_duration, Integer, required: false
          argument :expiration_at, GraphQL::Types::ISO8601DateTime, required: false
          argument :position, Integer, required: false

          type Types::Quotes::Object

          def resolve(quote_id:, id:, **args)
            quote = current_organization.quotes.find_by(id: quote_id)
            result = ::Quotes::BillingItems::Coupons::UpdateService.call(quote:, id:, params: args)
            result.success? ? result.quote : result_error(result)
          end
        end
      end
    end
  end
end
