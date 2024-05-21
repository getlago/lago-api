# frozen_string_literal: true

module Invoices
  class CreateService < BaseService
    def initialize(customer:, currency:, fees:, timestamp:)
      @customer = customer
      @currency = currency || customer&.currency
      @fees = fees
      @timestamp = timestamp

      super(nil)
    end

    def call
      return result.not_found_failure!(resource: 'customer') unless customer
      return result.not_found_failure!(resource: 'fees') if fees.blank?
      return result.not_found_failure!(resource: 'add_on') unless add_ons.count == add_on_identifiers.count

      ActiveRecord::Base.transaction do
        currency_result = Customers::UpdateService.new(nil).update_currency(customer:, currency:)
        return currency_result unless currency_result.success?

        create_generating_invoice
        create_one_off_fees(invoice)
        Invoices::ComputeAmountsFromFees.call(invoice:)
        invoice.payment_status = invoice.total_amount_cents.positive? ? :pending : :succeeded

        invoice.finalized!
      end

      track_invoice_created(invoice)
      SendWebhookJob.perform_later('invoice.one_off_created', invoice) if should_deliver_webhook?
      InvoiceMailer.with(invoice:).finalized.deliver_later if should_deliver_email?
      Integrations::Aggregator::Invoices::CreateJob.perform_later(invoice:) if invoice.should_sync_invoice?
      Integrations::Aggregator::SalesOrders::CreateJob.perform_later(invoice:) if invoice.should_sync_sales_order?
      Invoices::Payments::CreateService.new(invoice).call

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

    attr_accessor :timestamp, :currency, :customer, :fees, :invoice

    def create_generating_invoice
      invoice_result = Invoices::CreateGeneratingService.call(
        customer:,
        invoice_type: :one_off,
        currency:,
        datetime: Time.zone.at(timestamp),
      )
      invoice_result.raise_if_error!

      @invoice = invoice_result.invoice
    end

    def create_one_off_fees(invoice)
      fee_result = Fees::OneOffService.new(invoice:, fees:).create
      fee_result.raise_if_error!
    end

    def should_deliver_webhook?
      customer.organization.webhook_endpoints.any?
    end

    def track_invoice_created(invoice)
      SegmentTrackJob.perform_later(
        membership_id: CurrentContext.membership,
        event: 'invoice_created',
        properties: {
          organization_id: invoice.organization.id,
          invoice_id: invoice.id,
          invoice_type: invoice.invoice_type
        },
      )
    end

    def should_deliver_email?
      License.premium? && customer.organization.email_settings.include?('invoice.finalized')
    end

    def add_ons
      finder = api_context? ? :code : :id

      customer.organization.add_ons.where(finder => add_on_identifiers)
    end

    def add_on_identifiers
      identifier = api_context? ? :add_on_code : :add_on_id

      fees.pluck(identifier).uniq
    end
  end
end
