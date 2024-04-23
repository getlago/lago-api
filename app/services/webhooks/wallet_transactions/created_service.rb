# frozen_string_literal: true

module Webhooks
  module WalletTransactions
    class CreatedService < Webhooks::BaseService
      private

      def current_organization
        @current_organization ||= object.wallet.organization
      end

      def object_serializer
        ::V1::WalletTransactionSerializer.new(object, root_name: 'wallet_transaction')
      end

      def webhook_type
        'wallet_transaction.created'
      end

      def object_type
        'wallet_transaction'
      end
    end
  end
end
