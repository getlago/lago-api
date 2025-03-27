# frozen_string_literal: true

module Types
  module DataApi
    module RevenueStreams
      module Plans
        class Collection < Types::BaseObject
          graphql_name "DataApiRevenueStreamsPlans"

          field :revenue_streams_plans, [Types::DataApi::RevenueStreams::Plans::Object], null: false

          field :meta, Types::DataApi::Metadata, null: false
        end
      end
    end
  end
end
