# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module DataApi
    module RevenueStreams
      module Plans
        class Collection < Types::BaseObject
          graphql_name "DataApiRevenueStreamsPlans"

          field :collection, [Types::DataApi::RevenueStreams::Plans::Object], null: false

          field :metadata, Types::DataApi::Metadata, null: false
        end
      end
    end
  end
end
