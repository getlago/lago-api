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
          description "Updates a coupon billing item on a quote version"

          argument :quote_version_id, ID, required: true
          argument :id, ID, required: true
          argument :coupon_id, ID, required: false
          argument :coupon_type, String, required: false
          argument :amount_cents, GraphQL::Types::BigInt, required: false
          argument :amount_currency, String, required: false
          argument :percentage_rate, GraphQL::Types::Float, required: false

          type Types::QuoteVersions::Object

          def resolve(**args)
            quote_version = current_organization.quote_versions.find_by(id: args[:quote_version_id])
            result = ::Quotes::BillingItems::Coupons::UpdateService.call(
              quote_version:,
              id: args[:id],
              params: args.except(:quote_version_id, :id)
            )
            result.success? ? result.quote_version : result_error(result)
          end
        end
      end
    end
  end
end
