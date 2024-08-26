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
        create_fees
        create_applied_usage_thresholds

        invoice.fees_amount_cents = invoice.fees.sum(:amount_cents)
        invoice.sub_total_excluding_taxes_amount_cents = invoice.fees_amount_cents

        Credits::ProgressiveBillingService.call(invoice:)
        Credits::AppliedCouponsService.call(invoice:)
        Invoices::ComputeAmountsFromFees.call(invoice:)

        create_credit_note_credit
        create_applied_prepaid_credit

        invoice.payment_status = invoice.total_amount_cents.positive? ? :pending : :succeeded
        invoice.finalized!
      end

      # TODO: deduct previous progressive billing invoices

      Utils::SegmentTrack.invoice_created(invoice)
      SendWebhookJob.perform_later('invoice.created', invoice)
      Invoices::GeneratePdfAndNotifyJob.perform_later(invoice:, email: should_deliver_email?)
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

    def create_fees
      charges.find_each do |charge|
        Fees::ChargeService.call(invoice:, charge:, subscription:, boundaries:).raise_if_error!
      end
    end

    def charges
      subscription
        .plan
        .charges
        .joins(:billable_metric)
        .includes(:taxes, billable_metric: :organization, filters: {values: :billable_metric_filter})
        .where(invoiceable: true)
        .where(pay_in_advance: false)
        .where(billable_metrics: {recurring: false})
    end

    def boundaries
      return @boundaries if defined?(@boundaries)

      invoice_subscription = invoice.invoice_subscriptions.first
      date_service = Subscriptions::DatesService.new_instance(
        subscription,
        timestamp,
        current_usage: true
      )

      @boundaries = {
        from_datetime: invoice_subscription.from_datetime,
        to_datetime: invoice_subscription.to_datetime,
        charges_from_datetime: invoice_subscription.charges_from_datetime,
        charges_to_datetime: invoice_subscription.charges_to_datetime,
        timestamp: timestamp,
        charges_duration: date_service.charges_duration_in_days
      }
    end

    def create_applied_usage_thresholds
      usage_thresholds.each do
        AppliedUsageThreshold.create!(
          invoice:,
          usage_threshold: _1,
          lifetime_usage_amount_cents: lifetime_usage.total_amount_cents
        )
      end
    end

    def should_deliver_email?
      License.premium? && subscription.organization.email_settings.include?('invoice.finalized')
    end

    def create_credit_note_credit
      credit_result = Credits::CreditNoteService.call(invoice:).raise_if_error!

      invoice.total_amount_cents -= credit_result.credits.sum(&:amount_cents) if credit_result.credits
    end

    def create_applied_prepaid_credit
      wallet = subscription.customer.wallets.active.first
      return unless wallet&.active?
      return unless invoice.total_amount_cents.positive?
      return unless wallet.balance.positive?

      prepaid_credit_result = Credits::AppliedPrepaidCreditService.call(invoice:, wallet:).raise_if_error!

      invoice.total_amount_cents -= prepaid_credit_result.prepaid_credit_amount_cents
    end
  end
end
