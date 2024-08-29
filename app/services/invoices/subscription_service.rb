# frozen_string_literal: true

module Invoices
  class SubscriptionService < BaseService
    def initialize(subscriptions:, timestamp:, invoicing_reason:, invoice: nil, skip_charges: false)
      @subscriptions = subscriptions
      @timestamp = timestamp
      @invoicing_reason = invoicing_reason
      @recurring = invoicing_reason.to_sym == :subscription_periodic

      @customer = subscriptions&.first&.customer
      @currency = subscriptions&.first&.plan&.amount_currency

      # NOTE: In case of retry when the creation process failed,
      #       and if the generating invoice was persisted,
      #       the process can be retried without creating a new invoice
      @invoice = invoice
      @skip_charges = skip_charges

      super
    end

    def call
      return result if active_subscriptions.empty? && recurring

      create_generating_invoice unless invoice
      result.invoice = invoice

      fee_result = ActiveRecord::Base.transaction do
        invoice.status = invoice_status

        fee_result = Invoices::CalculateFeesService.call(
          invoice:,
          recurring:
        )

        # NOTE: We don't want to raise error and corrupt DB commit if there is tax error.
        #       In that case we want fees to stay attached to the invoice. There is retry action that will enable users
        #       to finalize invoice
        fee_result.raise_if_error! unless tax_error?(fee_result)
        invoice.reload

        flag_lifetime_usage_for_refresh
        fee_result
      end
      result.non_invoiceable_fees = fee_result.non_invoiceable_fees

      # non-invoiceable fees are created the first time, regardless of grace period.
      # Whenever the invoice is refreshed, the fees are not created again. (see `Fees::ChargeService.already_billed?`)
      # The webhook are sent whenever non-invoiceable fees are found in result.
      result.non_invoiceable_fees&.each do |fee|
        SendWebhookJob.perform_later('fee.created', fee)
      end

      if tax_error?(fee_result)
        SendWebhookJob.perform_later('invoice.drafted', invoice) if grace_period?

        return result.validation_failure!(errors: {tax_error: [fee_result.error.error_message]})
      end

      if grace_period?
        SendWebhookJob.perform_later('invoice.drafted', invoice)
      else
        SendWebhookJob.perform_later('invoice.created', invoice)
        GeneratePdfAndNotifyJob.perform_later(invoice:, email: should_deliver_finalized_email?)
        Integrations::Aggregator::Invoices::CreateJob.perform_later(invoice:) if invoice.should_sync_invoice?
        Integrations::Aggregator::SalesOrders::CreateJob.perform_later(invoice:) if invoice.should_sync_sales_order?
        Invoices::Payments::CreateService.new(invoice).call
        Utils::SegmentTrack.invoice_created(invoice)
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::ServiceFailure => e
      raise unless e.code.to_s == 'duplicated_invoices'
      raise unless invoicing_reason.to_sym == :subscription_periodic

      result
    rescue => e
      result.fail_with_error!(e)
    end

    private

    attr_accessor :subscriptions,
      :timestamp,
      :invoicing_reason,
      :recurring,
      :customer,
      :currency,
      :invoice,
      :skip_charges

    def active_subscriptions
      @active_subscriptions ||= subscriptions.select(&:active?)
    end

    def create_generating_invoice
      invoice_result = Invoices::CreateGeneratingService.call(
        customer:,
        invoice_type: :subscription,
        currency:,
        datetime: Time.zone.at(timestamp),
        skip_charges:
      ) do |invoice|
        Invoices::CreateInvoiceSubscriptionService
          .call(invoice:, subscriptions:, timestamp:, invoicing_reason:)
          .raise_if_error!
      end

      invoice_result.raise_if_error!

      @invoice = invoice_result.invoice
    end

    def grace_period?
      @grace_period ||= customer.applicable_invoice_grace_period.positive?
    end

    def invoice_status
      grace_period? ? :draft : :finalized
    end

    def should_deliver_finalized_email?
      License.premium? &&
        customer.organization.email_settings.include?('invoice.finalized')
    end

    def flag_lifetime_usage_for_refresh
      LifetimeUsages::FlagRefreshFromInvoiceService.call(invoice:).raise_if_error!
    end

    def tax_error?(fee_result)
      !fee_result.success? && fee_result&.error&.code == 'tax_error'
    end
  end
end
