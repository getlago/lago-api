# frozen_string_literal: true

module Resolvers
  module DataApi
    class MrrsResolver < Resolvers::BaseResolver
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "data_api:view"

      graphql_name "DataApiMrrs"
      description "Query monthly recurring revenues of an organization"

      argument :currency, Types::CurrencyEnum, required: false

      argument :customer_country, Types::CountryCodeEnum, required: false
      argument :customer_type, Types::Customers::CustomerTypeEnum, required: false

      argument :from_date, GraphQL::Types::ISO8601Date, required: false
      argument :to_date, GraphQL::Types::ISO8601Date, required: false

      argument :time_granularity, Types::DataApi::TimeGranularityEnum, required: false

      argument :external_customer_id, String, required: false
      argument :external_subscription_id, String, required: false

      argument :plan_code, String, required: false

      type Types::DataApi::Mrrs::Object.collection_type, null: false

      def resolve(**args)
        result = ::DataApi::MrrsService.call(current_organization, **args)
        result.mrrs
      end
    end
  end
end
