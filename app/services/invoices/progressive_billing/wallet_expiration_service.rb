# frozen_string_literal: true

module Invoices
  module ProgressiveBilling
    class WalletExpirationService < BaseService
      def initialize(wallet:, subscription:, timestamp: Time.current)
        @wallet = wallet
        @subscription = subscription

        super(timestamp:)
      end

      # Without credits left, the wallet would pay for none of the usage.
      def call
        if wallet.balance_cents.positive?
          super
        else
          result
        end
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

      # The wallet pays for the usage until it expires, not until the expiration job runs.
      def boundaries
        return @boundaries if defined?(@boundaries)

        super.tap do |boundaries|
          boundaries.charges_to_datetime = [wallet.expiration_at, boundaries.charges_to_datetime].compact.min
        end
      end

      def create_fees
        super if boundaries.charges_to_datetime > boundaries.charges_from_datetime
      end
    end
  end
end
