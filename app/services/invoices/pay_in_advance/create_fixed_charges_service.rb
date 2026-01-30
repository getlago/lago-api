# frozen_string_literal: true

module Invoices
  module PayInAdvance
    class CreateFixedChargesService < Invoices::PayInAdvance::BaseService
      Result = BaseResult[:invoice]

      def initialize(subscription:, timestamp:)
        @subscription = subscription
        @timestamp = timestamp
        @customer = subscription.customer
        @organization = subscription.organization

        super
      end

      def call
        return result unless subscription.active?
        return result if fixed_charge_events.empty?

        # Calculate fees for all fixed charge events
        fees = calculate_all_fees
        # Invoice without fees should be created if there are no fees to bill
        # return result if fees.empty?

        ActiveRecord::Base.transaction do
          # We acquire a lock on the customer to prevent concurrent pay-in-advance invoice creation.
          ApplicationRecord.with_advisory_lock!(customer_lock_key, timeout_seconds: ACQUIRE_LOCK_TIMEOUT, transaction: true) do
            create_generating_invoice
            fees.each do |fee|
              fee.invoice = invoice
              fee.save!
            end

            apply_fees_and_coupons

            Invoices::ComputeAmountsFromFees.call(invoice:)
            apply_credits
            finalize_invoice
          end
        end

        result.invoice = invoice
        trigger_post_creation_jobs

        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      rescue Sequenced::SequenceError, ActiveRecord::StaleObjectError, WithAdvisoryLock::FailedToAcquireLock
        raise
      rescue => e
        result.fail_with_error!(e)
      end

      private

      attr_reader :subscription, :timestamp, :customer, :organization

      def fixed_charge_events
        @fixed_charge_events ||= subscription
          .fixed_charge_events
          .where(
            fixed_charge: subscription.fixed_charges.pay_in_advance,
            timestamp: Time.zone.at(timestamp)
          )
      end

      def calculate_all_fees
        fees = []

        fixed_charge_events.each do |event|
          fixed_charge = event.fixed_charge
          next unless fixed_charge.pay_in_advance?

          fee_result = Fees::BuildPayInAdvanceFixedChargeService.call!(
            subscription:,
            fixed_charge:,
            fixed_charge_event: event,
            timestamp:
          )

          fees << fee_result.fee if fee_result.fee
        end

        fees
      end

      def create_generating_invoice
        invoice_result = Invoices::CreateGeneratingService.call(
          customer:,
          invoice_type: :subscription,
          currency: customer.currency,
          datetime: Time.zone.at(timestamp),
          charge_in_advance: true
        ) do |inv|
          Invoices::CreateInvoiceSubscriptionService
            .call(invoice: inv, subscriptions: [subscription], timestamp:, invoicing_reason: :in_advance_charge)
            .raise_if_error!
        end
        invoice_result.raise_if_error!

        @invoice = invoice_result.invoice
      end

      def wallets
        @wallets ||= customer.wallets.active.includes(:wallet_targets)
          .with_positive_balance.in_application_order
      end

      def should_create_applied_prepaid_credit?
        return false unless invoice.total_amount_cents&.positive?

        wallets.any?
      end
    end
  end
end
