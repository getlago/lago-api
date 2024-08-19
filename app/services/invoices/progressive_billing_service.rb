# frozen_string_literal: true

module Invoices
  class ProgressiveBillingService < BaseService
    def initialize(usage_thresholds:, lifetime_usage:, timestamp: Time.current)
      @usage_thresholds = usage_thresholds
      @lifetime_usage = lifetime_usage
      @timestamp = timestamp

      super
    end

    def call
      ActiveRecord::Base.transaction do
        create_generating_invoice
        create_threshold_fees
        Invoices::ComputeAmountsFromFees.call(invoice:)
        invoice.finalized!
      end

      Utils::SegmentTrack.invoice_created(invoice)
      SendWebhookJob.perform_later('invoice.created', invoice)
      GeneratePdfAndNotifyJob.perform_later(invoice:, email: should_deliver_email?)
      Integrations::Aggregator::Invoices::CreateJob.perform_later(invoice:) if invoice.should_sync_invoice?
      Integrations::Aggregator::SalesOrders::CreateJob.perform_later(invoice:) if invoice.should_sync_sales_order?
      Invoices::Payments::CreateService.call(invoice)

      result.invoice = invoice
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue Sequenced::SequenceError
      raise
    rescue => e
      result.fail_with_error!(e)
    end

    private

    attr_accessor :usage_thresholds, :lifetime_usage, :timestamp, :invoice

    delegate :subscription, to: :lifetime_usage

    def create_generating_invoice
      invoice_result = CreateGeneratingService.call(
        customer: subscription.customer,
        invoice_type: :progressive_billing,
        currency: usage_thresholds.first.plan.amount_currency,
        datetime: Time.zone.at(timestamp)
      ) do |invoice|
        CreateInvoiceSubscriptionService
          .call(invoice:, subscriptions: [subscription], timestamp:, invoicing_reason: :progressive_billing)
          .raise_if_error!
      end
      invoice_result.raise_if_error!

      @invoice = invoice_result.invoice
    end

    def sorted_thresholds
      fixed = usage_thresholds.select { |t| !t.recurring }.sort_by(&:amount_cents)
      recurring = usage_thresholds.select(&:recurring)
      fixed + recurring
    end

    def create_threshold_fees
      sorted_thresholds.each do |usage_threshold|
        fee_result = Fees::CreateFromUsageThresholdService
          .call(usage_threshold:, invoice:, amount_cents: amount_cents(usage_threshold))
        fee_result.raise_if_error!
        fee_result.fee
      end
    end

    def should_deliver_email?
      License.premium? && subscription.organization.email_settings.include?('invoice.finalized')
    end

    def amount_cents(usage_threshold)
      if usage_threshold.recurring?
        # NOTE: Recurring is always the last threshold.
        #       Amount is the current lifetime usage without already invoiced thresholds
        #       The recurring threshold can be reached multiple time, so we need to compute the number of times
        units = (total_lifetime_usage_amount_cents - invoiced_amount_cents) / usage_threshold.amount_cents
        units * usage_threshold.amount_cents
      else
        # NOTE: Amount to bill if the current threshold minus the usage that have already been invoiced
        result_amount = usage_threshold.amount_cents - invoiced_amount_cents

        # NOTE: Add the amount to the invoiced_amount_cents for next non recurring threshold
        @invoiced_amount_cents += result_amount

        result_amount
      end
    end

    # NOTE: Sum of usage that have already been invoiced
    def invoiced_amount_cents
      @invoiced_amount_cents ||= subscription.invoices
        .finalized
        .where(invoice_type: %w[subscription progressive_billing])
        .sum { |invoice| invoice.fees.where(fee_type: %w[charge progressive_billing]).sum(:amount_cents) }
    end

    # NOTE: Current lifetime usage amount
    def total_lifetime_usage_amount_cents
      @total_lifetime_usage_amount_cents ||= lifetime_usage.invoiced_usage_amount_cents + lifetime_usage.current_usage_amount_cents
    end
  end
end
