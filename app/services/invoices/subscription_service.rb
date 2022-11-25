# frozen_string_literal: true

module Invoices
  class SubscriptionService < BaseService
    def initialize(subscriptions:, timestamp:, recurring:)
      @subscriptions = subscriptions
      @timestamp = timestamp
      @recurring = recurring
      @customer = subscriptions&.first&.customer
      @currency = subscriptions&.first&.plan&.amount_currency

      super(nil)
    end

    def create
      result = nil
      invoice = nil

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
          timezone: customer.applicable_timezone,
          status: invoice_status,
        )

        result = Invoices::CalculateFeesService.new(
          invoice: invoice,
          subscriptions: subscriptions,
          timestamp: timestamp,
          recurring: recurring,
        ).call

        unless grace_period?
          SendWebhookJob.perform_later(:invoice, result.invoice) if should_deliver_webhook?
          create_payment(result.invoice)
          track_invoice_created(result.invoice)
        end

        result
      end

      SendWebhookJob.perform_later(:invoice, invoice) if should_deliver_webhook?
      Invoices::Payments::CreateService.new(invoice).call
      track_invoice_created(invoice)

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_accessor :subscriptions, :timestamp, :recurring, :customer, :currency

    def issuing_date
      Time.zone.at(timestamp).in_time_zone(customer.applicable_timezone).to_date
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
