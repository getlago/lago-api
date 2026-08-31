# frozen_string_literal: true

module Webhooks
  module Wallets
    class UpdatedService < Webhooks::BaseService
      private

      def object_serializer
        ::V1::WalletSerializer.new(object, root_name: "wallet", includes: %i[recurring_transaction_rules])
      end

      def webhook_type
        "wallet.updated"
      end

      def object_type
        "wallet"
      end

      # Groups every change to one customer onto a single Kinesis shard, so a
      # consumer can process that customer's records on one worker.
      def partition_key
        object.customer.external_id
      end
    end
  end
end
