# frozen_string_literal: true

module Resolvers
  module DataApi
    module Mrrs
      class PlansResolver < Resolvers::BaseResolver
        include AuthenticableApiUser
        include RequiredOrganization

        REQUIRED_PERMISSION = "data_api:view"

        graphql_name "DataApiMrrsPlans"
        description "Query monthly recurring revenues plans of an organization"

        argument :currency, Types::CurrencyEnum, required: false
        argument :limit, Integer, required: false
        argument :page, Integer, required: false

        type Types::DataApi::Mrrs::Plans::Collection, null: false

        def resolve(**args)
          result = ::DataApi::Mrrs::PlansService.call(current_organization, **args)
          result.data_mrrs_plans
        end
      end
    end
  end
end
