# frozen_string_literal: true

module Invoices
  module ProgressiveBilling
    class BaseService < ::BaseService
      Result = BaseResult[:invoice]

      def initialize(timestamp: Time.current)
        @timestamp = timestamp

        super
      end

      def call
        Idempotency.transaction do
          create_generating_invoice
          create_fees
          after_fees_created

          Idempotency.unique!(invoice,
            organization_id: subscription.organization_id,
            external_subscription_id: subscription.external_id,
            **idempotency_values)

          invoice.fees_amount_cents = invoice.fees.sum(:amount_cents)
          invoice.sub_total_excluding_taxes_amount_cents = invoice.fees_amount_cents

          credits = Credits::ProgressiveBillingService.call(invoice:).credits
          after_progressive_billing_credits_applied(credits)
          Credits::AppliedCouponsService.call(invoice:)
          Invoices::ApplyInvoiceCustomSectionsService.call(invoice:)

          totals_result = Invoices::ComputeTaxesAndTotalsService.call(invoice:)
          next if !totals_result.success? && totals_result.error.is_a?(::BaseService::UnknownTaxFailure)

          totals_result.raise_if_error!

          create_credit_note_credit
          create_applied_prepaid_credit

          invoice.payment_status = invoice.total_amount_cents.positive? ? :pending : :succeeded
          Invoices::FinalizeService.call!(invoice: invoice)
        end

        if invoice.finalized?
          SendWebhookJob.perform_later("invoice.created", invoice)
          Utils::ActivityLog.produce(invoice, "invoice.created")
          Invoices::GenerateDocumentsJob.perform_later(invoice:, notify: should_deliver_email?)
          Integrations::Aggregator::Invoices::CreateJob.perform_later(invoice:) if invoice.should_sync_invoice?
          Integrations::Aggregator::Invoices::Hubspot::CreateJob.perform_later(invoice:) if invoice.should_sync_hubspot_invoice?
          Invoices::Payments::CreateService.call_async(invoice:)
        end

        result.invoice = invoice
        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      rescue Sequenced::SequenceError, ActiveRecord::StaleObjectError, BaseLockService::FailedToAcquireLock
        raise
      rescue => e
        result.fail_with_error!(e)
      end

      private

      attr_accessor :timestamp, :invoice

      def subscription
        raise NotImplementedError
      end

      def idempotency_values
        raise NotImplementedError
      end

      def after_fees_created
      end

      def after_progressive_billing_credits_applied(credits)
      end

      def create_generating_invoice
        invoice_result = CreateGeneratingService.call(
          customer: subscription.customer,
          invoice_type: :progressive_billing,
          currency: subscription.plan.amount_currency,
          datetime: Time.zone.at(timestamp),
          billing_entity: subscription.billing_entity || subscription.customer.billing_entity,
          purchase_order_number: subscription.purchase_order_number
        ) do |invoice|
          CreateInvoiceSubscriptionService
            .call(invoice:, subscriptions: [subscription], timestamp:, invoicing_reason: :progressive_billing)
            .raise_if_error!
        end
        invoice_result.raise_if_error!

        @invoice = invoice_result.invoice
      end

      def create_fees
        filters = event_filters(subscription, boundaries).filter_targets

        charges.find_each do |charge|
          Fees::ChargeService.call!(
            invoice:,
            metered_item: Fees::ChargeService::MeteredItem.from_charge(charge:, boundaries:),
            billing_context: Billing::Context.from(subscription:),
            options: Fees::ChargeService::Options.new(context: :finalize),
            filtered_aggregations: filters[charge.target_key]&.keys || []
          )
        end
      end

      def charges
        subscription
          .plan
          .charges
          .includes(:taxes, billable_metric: :organization, filters: {values: :billable_metric_filter})
          .where(invoiceable: true)
          .where(pay_in_advance: false)
      end

      def boundaries
        return @boundaries if defined?(@boundaries)

        invoice_subscription = invoice.invoice_subscriptions.first
        date_service = Subscriptions::DatesService.new_instance(
          subscription,
          timestamp,
          current_usage: true
        )

        @boundaries = BillingPeriodBoundaries.new(
          from_datetime: invoice_subscription.from_datetime,
          to_datetime: invoice_subscription.to_datetime,
          charges_from_datetime: invoice_subscription.charges_from_datetime,
          charges_to_datetime: invoice_subscription.charges_to_datetime,
          timestamp: timestamp,
          charges_duration: date_service.charges_duration_in_days
        )
      end

      def should_deliver_email?
        License.premium? && invoice.billing_entity.email_settings.include?("invoice.finalized")
      end

      def create_credit_note_credit
        credit_result = Credits::CreditNoteService.call(invoice:).raise_if_error!

        invoice.total_amount_cents -= credit_result.credits.sum(&:amount_cents) if credit_result.credits
      end

      def create_applied_prepaid_credit
        return unless invoice.total_amount_cents.positive?

        prepaid_credit_result = Credits::AppliedPrepaidCreditsService.call!(invoice:)
        invoice.total_amount_cents -= prepaid_credit_result.prepaid_credit_amount_cents
      end

      def event_filters(subscription, boundaries)
        Events::BillingPeriodFilterService.for_charges!(
          subscription:, boundaries:, with_last_seen_at: false
        )
      end
    end
  end
end
