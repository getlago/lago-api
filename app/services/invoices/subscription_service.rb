# frozen_string_literal: true

module Invoices
  class SubscriptionService < BaseService
    def initialize(subscriptions:, timestamp:, recurring:, invoice: nil, skip_charge: false)
      @subscriptions = subscriptions
      @timestamp = timestamp

      # NOTE: Billed automatically by the recurring billing process
      #       It is used to prevent double billing on billing day
      @recurring = recurring

      @customer = subscriptions&.first&.customer
      @currency = subscriptions&.first&.plan&.amount_currency

      # NOTE: In case of retry when the creation process failed,
      #       and if the generating invoice was persisted,
      #       the process can be retried without creating a new invoice
      @invoice = invoice

      @skip_charge = skip_charge

      super
    end

    def call
      return result if active_subscriptions.empty? && recurring

      create_generating_invoice unless invoice
      result.invoice = invoice

      ActiveRecord::Base.transaction do
        invoice.status = invoice_status
        invoice.save!

        fee_result = Invoices::CalculateFeesService.call(
          invoice:,
          recurring:,
          skip_charge:,
        )

        fee_result.raise_if_error!
        invoice.reload
      end

      if grace_period?
        SendWebhookJob.perform_later('invoice.drafted', invoice) if should_deliver_webhook?
      else
        SendWebhookJob.perform_later('invoice.created', invoice) if should_deliver_webhook?
        InvoiceMailer.with(invoice:).finalized.deliver_later if should_deliver_finalized_email?
        Invoices::Payments::CreateService.new(invoice).call
        track_invoice_created(invoice)
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue Sequenced::SequenceError
      raise
    rescue StandardError => e
      result.fail_with_error!(e)
    end

    private

    attr_accessor :subscriptions, :timestamp, :recurring, :customer, :currency, :invoice, :skip_charge

    def active_subscriptions
      @active_subscriptions ||= subscriptions.select(&:active?)
    end

    def create_generating_invoice
      invoice_result = Invoices::CreateGeneratingService.call(
        customer:,
        invoice_type: :subscription,
        currency:,
        datetime: Time.zone.at(timestamp),
      ) do |invoice|
        Invoices::CreateInvoiceSubscriptionService
          .call(invoice:, subscriptions:, timestamp:, recurring:)
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

    def should_deliver_webhook?
      customer.organization.webhook_endpoints.any?
    end

    def should_deliver_finalized_email?
      License.premium? &&
        customer.organization.email_settings.include?('invoice.finalized')
    end

    def track_invoice_created(invoice)
      SegmentTrackJob.perform_later(
        membership_id: CurrentContext.membership,
        event: 'invoice_created',
        properties: {
          organization_id: invoice.organization.id,
          invoice_id: invoice.id,
          invoice_type: invoice.invoice_type,
        },
      )
    end
  end
end
