# frozen_string_literal: true

module Invoices
  class CreateOneOffService < BaseService
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
        currency_result.raise_if_error!

        create_generating_invoice

        fees_result = create_one_off_fees(invoice)
        if tax_error?(fees_result)
          invoice.fees_amount_cents = invoice.fees.sum(:amount_cents)
          invoice.sub_total_excluding_taxes_amount_cents = invoice.fees_amount_cents
          invoice.failed!

          return result.validation_failure!(errors: {tax_error: [fees_result.error.error_message]})
        end

        Invoices::ComputeAmountsFromFees.call(invoice:, provider_taxes: result.fees_taxes)
        invoice.payment_status = invoice.total_amount_cents.positive? ? :pending : :succeeded

        invoice.finalized!
      end

      Utils::SegmentTrack.invoice_created(invoice)
      SendWebhookJob.perform_later('invoice.one_off_created', invoice)
      GeneratePdfAndNotifyJob.perform_later(invoice:, email: should_deliver_email?)
      Integrations::Aggregator::Invoices::CreateJob.perform_later(invoice:) if invoice.should_sync_invoice?
      Integrations::Aggregator::SalesOrders::CreateJob.perform_later(invoice:) if invoice.should_sync_sales_order?
      Invoices::Payments::CreateService.new(invoice).call

      result.invoice = invoice
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue Sequenced::SequenceError
      raise
    rescue BaseService::FailedResult => e
      e.result
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
        datetime: Time.zone.at(timestamp)
      )
      invoice_result.raise_if_error!

      @invoice = invoice_result.invoice
    end

    def create_one_off_fees(invoice)
      fees_result = Fees::OneOffService.new(invoice:, fees:).create
      fees_result.raise_if_error! unless tax_error?(fees_result)

      result.fees_taxes = fees_result.fees_taxes

      fees_result
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

    def tax_error?(fee_result)
      !fee_result.success? && fee_result.error.code == 'tax_error'
    end
  end
end
