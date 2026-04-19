# frozen_string_literal: true

module Mutations
  module Quotes
    module BillingItems
      module Coupons
        class Add < BaseMutation
          include AuthenticableApiUser
          include RequiredOrganization

          REQUIRED_PERMISSION = "quotes:update"
          graphql_name "AddQuoteCoupon"
          description "Adds a coupon billing item to a draft quote"

          argument :amount_cents, GraphQL::Types::BigInt, required: false
          argument :coupon_id, ID, required: true
          argument :coupon_type, String, required: true
          argument :currency, String, required: false
          argument :expiration_at, GraphQL::Types::ISO8601DateTime, required: false
          argument :frequency, String, required: false
          argument :frequency_duration, Integer, required: false
          argument :percentage_rate, Float, required: false
          argument :position, Integer, required: false
          argument :quote_id, ID, required: true

          type Types::Quotes::Object

          def resolve(quote_id:, **args)
            quote = current_organization.quotes.find_by(id: quote_id)
            result = ::Quotes::BillingItems::Coupons::AddService.call(quote:, params: args)
            result.success? ? result.quote : result_error(result)
          end
        end
      end
    end
  end
end
