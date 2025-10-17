# frozen_string_literal: true

module Types
  module Wallets
    class Metadata < GraphqlPagination::CollectionMetadataType
      graphql_name "WalletCollectionMetadata"
      field :customer_active_wallets_count, Integer, null: false

      def customer_active_wallets_count
        # Get customer from the first wallet in the collection
        collection = object.items
        return 0 if collection.empty?

        collection.first.customer.wallets.active.count
      end
    end
  end
end
