# frozen_string_literal: true

module Resolvers
  module DataApi
    module RevenueStreams
      class PlansResolver < Resolvers::BaseResolver
        include AuthenticableApiUser
        include RequiredOrganization

        REQUIRED_PERMISSION = "data_api:view"

        graphql_name "DataApiRevenueStreamsPlans"
        description "Query revenue streams plans of an organization"

        argument :currency, Types::CurrencyEnum, required: false
        argument :limit, Integer, required: false
        argument :offset, Integer, required: false
        argument :order_by, Types::DataApi::RevenueStreams::OrderByEnum, required: false

        type Types::DataApi::RevenueStreams::Plans::Object.collection_type, null: false

        def resolve(**args)
          result = ::DataApi::RevenueStreams::PlansService.call(current_organization, **args)
          result.revenue_streams_plans
        end
      end
    end
  end
end
