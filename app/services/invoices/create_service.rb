# frozen_string_literal: true

module Invoices
  class CreateService < BaseService
    def initialize(subscriptions:, timestamp:)
      @subscriptions = subscriptions
      @timestamp = timestamp
      @customer = subscriptions&.first&.customer
      @currency = subscriptions&.first&.plan&.amount_currency

      super(nil)
    end

    def create
      ActiveRecord::Base.transaction do
        invoice = Invoice.create!(
          customer: customer,
          issuing_date: issuing_date,
          invoice_type: :subscription,

          amount_currency: currency,
          vat_amount_currency: currency,
          credit_amount_currency: currency,
          total_amount_currency: currency,
          vat_rate: customer.applicable_vat_rate,
        )

        subscriptions.each { |subscription| invoice.subscriptions << subscription }

        result = Invoices::CalculateFeesService.new(
          invoice: invoice,
          timestamp: timestamp,
        ).call

        SendWebhookJob.perform_later(:invoice, invoice) if should_deliver_webhook?
        Invoices::Payments::CreateService.new(invoice).call
        track_invoice_created(invoice)

        result
      end
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_accessor :subscriptions, :timestamp, :customer, :currency

    def issuing_date
      Time.zone.at(timestamp).in_time_zone(customer.applicable_timezone).to_date
    end

    def should_deliver_webhook?
      customer.organization.webhook_url?
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
