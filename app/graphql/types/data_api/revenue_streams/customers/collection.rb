# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module DataApi
    module RevenueStreams
      module Customers
        class Collection < Types::BaseObject
          graphql_name "DataApiRevenueStreamsCustomers"

          field :collection, [Types::DataApi::RevenueStreams::Customers::Object], null: false

          field :metadata, Types::DataApi::Metadata, null: false
        end
      end
    end
  end
end
