# frozen_string_literal: true

module Types
  module DataApi
    module RevenueStreams
      module Customers
        class Collection < Types::BaseObject
          graphql_name "DataApiRevenueStreamsCustomers"

          field :revenue_streams_customers, [Types::DataApi::RevenueStreams::Customers::Object], null: false

          field :meta, Types::DataApi::Metadata, null: false
        end
      end
    end
  end
end
