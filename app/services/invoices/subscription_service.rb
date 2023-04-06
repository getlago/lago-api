# frozen_string_literal: true

module Invoices
  class SubscriptionService < BaseService
    def initialize(subscriptions:, timestamp:, recurring:)
      @subscriptions = subscriptions
      @timestamp = timestamp

      # NOTE: Billed automatically by the recurring billing process
      #       It is used to prevent double billing on billing day
      @recurring = recurring

      @customer = subscriptions&.first&.customer
      @currency = subscriptions&.first&.plan&.amount_currency

      super
    end

    def create
      active_subscriptions = subscriptions.select(&:active?)
      return result if active_subscriptions.empty? && recurring

      result = nil
      invoice = nil

      ActiveRecord::Base.transaction do
        invoice = Invoice.create!(
          organization: customer.organization,
          customer:,
          issuing_date:,
          invoice_type: :subscription,
          amount_currency: currency,
          vat_amount_currency: currency,
          credit_amount_currency: currency,
          total_amount_currency: currency,
          vat_rate: customer.applicable_vat_rate,
          timezone: customer.applicable_timezone,
          status: invoice_status,
        )

        result = Invoices::CalculateFeesService.new(
          invoice:,
          subscriptions: recurring ? active_subscriptions : subscriptions,
          timestamp:,
          recurring:,
        ).call
      end

      result.raise_if_error!

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
    end

    private

    attr_accessor :subscriptions, :timestamp, :recurring, :customer, :currency

    def issuing_date
      issuing_date = Time.zone.at(timestamp).in_time_zone(customer.applicable_timezone).to_date
      return issuing_date unless grace_period?

      issuing_date + customer.applicable_invoice_grace_period.days
    end

    def grace_period?
      @grace_period ||= customer.applicable_invoice_grace_period.positive?
    end

    def invoice_status
      grace_period? ? :draft : :finalized
    end

    def should_deliver_webhook?
      customer.organization.webhook_url?
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
