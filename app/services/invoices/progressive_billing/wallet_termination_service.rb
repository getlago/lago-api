# frozen_string_literal: true

module Invoices
  module ProgressiveBilling
    class WalletTerminationService < BaseService
      def initialize(wallet:, subscription:, timestamp: Time.current)
        @wallet = wallet
        @subscription = subscription

        super(timestamp:)
      end

      private

      attr_reader :wallet, :subscription

      def progressive_billing_trigger
        :wallet_expiration
      end

      def idempotency_values
        {wallet_id: wallet.id}
      end

      def after_fees_created
        AppliedWalletExpiration.create!(organization_id: wallet.organization_id, invoice:, wallet:)
      end

      def nothing_to_invoice?
        invoice.fees_amount_cents <= invoice.progressive_billing_credit_amount_cents
      end
    end
  end
end
