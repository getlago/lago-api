# frozen_string_literal: true

module Invoices
  class OneOffService < BaseService
    def initialize(customer:, currency:, fees:, timestamp:)
      @customer = customer
      @currency = currency || customer&.currency
      @fees = fees
      @timestamp = timestamp

      super(nil)
    end

    def create
      return result.not_found_failure!(resource: 'customer') unless customer
      return result.not_found_failure!(resource: 'fees') if fees.blank?
      return result.not_found_failure!(resource: 'add_on') unless add_ons.count == add_on_identifiers.count

      invoice = nil

      ActiveRecord::Base.transaction do
        currency_result = Customers::UpdateService.new(nil).update_currency(customer:, currency:)
        return currency_result unless currency_result.success?

        invoice = Invoice.create!(
          organization: customer.organization,
          customer:,
          issuing_date:,
          invoice_type: :one_off,
          payment_status: :pending,
          currency:,
          vat_rate: customer.applicable_vat_rate,
          timezone: customer.applicable_timezone,
          status: :finalized,
        )

        create_one_off_fees(invoice)
        Invoices::ComputeAmountsFromFees.call(invoice:)

        invoice.save!
      end

      track_invoice_created(invoice)
      SendWebhookJob.perform_later('invoice.one_off_created', invoice) if should_deliver_webhook?
      InvoiceMailer.with(invoice:).finalized.deliver_later if should_deliver_email?
      Invoices::Payments::CreateService.new(invoice).call

      result.invoice = invoice
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_accessor :timestamp, :currency, :customer, :fees

    def create_one_off_fees(invoice)
      fee_result = Fees::OneOffService.new(invoice:, fees:).create
      fee_result.raise_if_error!
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

    # NOTE: accounting date must be in customer timezone
    def issuing_date
      Time.zone.at(timestamp).in_time_zone(customer.applicable_timezone).to_date
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
