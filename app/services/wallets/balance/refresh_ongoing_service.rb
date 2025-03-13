# frozen_string_literal: true

module Wallets
  module Balance
    class RefreshOngoingService < BaseService
      def initialize(wallet:)
        @wallet = wallet
        super
      end

      def call
        usage_amount_cents = customer.active_subscriptions.map do |subscription|
          customer_usage_result = ::Invoices::CustomerUsageService.call(customer:, subscription:)
          return customer_usage_result if customer_usage_result.failure?
          invoice = customer_usage_result.invoice

          {
            total_usage_amount_cents: invoice.total_amount.to_f * wallet.ongoing_balance.currency.subunit_to_unit,
            billed_usage_amount_cents: billed_usage_amount_cents(invoice)
          }
        end

        total_usage_amount_cents = usage_amount_cents.sum { |e| e[:total_usage_amount_cents] }
        billed_usage_amount_cents = usage_amount_cents.sum { |e| e[:billed_usage_amount_cents] }

        Wallets::Balance::UpdateOngoingService.call(wallet:, total_usage_amount_cents:, billed_usage_amount_cents:).raise_if_error!

        result.wallet = wallet
        result
      end

      private

      attr_reader :wallet

      delegate :customer, to: :wallet

      def billed_usage_amount_cents(invoice)
        paid_in_advance_fees = invoice.fees.select { |f| f.charge.pay_in_advance? && f.charge.invoiceable? }
        invoice.prepaid_credit_amount_cents +
          invoice.total_paid_amount_cents +
          # In invoice total that is returned from CustomerUsageService in total_usage the taxes are included
          # so if the fees ae already paid, we should exclude fees AND their taxes
          paid_in_advance_fees.sum(&:amount_cents) +
          paid_in_advance_fees.sum(&:taxes_amount_cents)
      end
    end
  end
end
