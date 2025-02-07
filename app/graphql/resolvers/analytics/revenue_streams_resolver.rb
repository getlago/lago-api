# frozen_string_literal: true

module Resolvers
  module Analytics
    class RevenueStreamsResolver < Resolvers::BaseResolver
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "analytics:view"

      description "Query revenue streams of an organization"

      argument :country, Types::CountryCodeEnum, required: false
      argument :currency, Types::CurrencyEnum, required: false
      argument :from_date, GraphQL::Types::ISO8601Date, required: false
      argument :to_date, GraphQL::Types::ISO8601Date, required: false

      argument :customer_type, Types::Customers::CustomerTypeEnum, required: false
      argument :external_customer_id, String, required: false
      argument :external_subscription_id, String, required: false
      argument :plan_code, String, required: false

      type Types::Analytics::RevenueStreams::Object.collection_type, null: false

      def resolve(**args)
        raise unauthorized_error unless License.premium?

        result = ::Analytics::RevenueStreamsService.call(current_organization, **args)
        result.revenue_streams
      end
    end
  end
end
