# frozen_string_literal: true

module Mutations
  module Quotes
    module BillingItems
      module Coupons
        class Remove < BaseMutation
          include AuthenticableApiUser
          include RequiredOrganization

          REQUIRED_PERMISSION = "quotes:update"
          graphql_name "RemoveQuoteCoupon"
          description "Removes a coupon billing item from a draft quote"

          argument :quote_id, ID, required: true
          argument :id, ID, required: true

          type Types::Quotes::Object

          def resolve(quote_id:, id:)
            quote = current_organization.quotes.find_by(id: quote_id)
            result = ::Quotes::BillingItems::Coupons::RemoveService.call(quote:, id:)
            result.success? ? result.quote : result_error(result)
          end
        end
      end
    end
  end
end
