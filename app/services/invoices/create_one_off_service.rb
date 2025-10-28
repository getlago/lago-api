# frozen_string_literal: true

module Invoices
  class CreateOneOffService < BaseService
    def initialize(customer:, currency:, fees:, timestamp:, skip_psp: false, voided_invoice_id: nil)
      @customer = customer
      @currency = currency || customer&.currency
      @fees = fees
      @timestamp = timestamp
      @skip_psp = skip_psp
      @voided_invoice_id = voided_invoice_id

      super(nil)
    end

    activity_loggable(
      action: "invoice.one_off_created",
      record: -> { result.invoice }
    )

    def call
      return result.not_found_failure!(resource: "customer") unless customer
      return result.not_found_failure!(resource: "fees") if fees.blank?
      return result.not_found_failure!(resource: "add_on") unless add_ons.count == add_on_identifiers.count

      ActiveRecord::Base.transaction do
        Customers::UpdateCurrencyService
          .call(customer:, currency:)
          .raise_if_error!

        create_generating_invoice

        result.invoice = invoice

        fees_result = create_one_off_fees(invoice)
        if tax_error?(fees_result)
          invoice.fees_amount_cents = invoice.fees.sum(:amount_cents)
          invoice.sub_total_excluding_taxes_amount_cents = invoice.fees_amount_cents
          invoice.failed!
          Utils::ActivityLog.produce(invoice, "invoice.failed")

          # TODO: Refactor this return by using a next method
          # rubocop:disable Rails/TransactionExitStatement
          return result
          # rubocop:enable Rails/TransactionExitStatement
        end

        Invoices::ComputeAmountsFromFees.call(invoice:, provider_taxes: result.fees_taxes)
        Invoices::ApplyInvoiceCustomSectionsService.call(invoice:)
        invoice.payment_status = invoice.total_amount_cents.positive? ? :pending : :succeeded
        Invoices::TransitionToFinalStatusService.call(invoice:)
        invoice.voided_invoice_id = voided_invoice_id if voided_invoice_id.present?
        invoice.save!
      end

      unless invoice.closed?
        Utils::SegmentTrack.invoice_created(invoice)
        SendWebhookJob.perform_later("invoice.one_off_created", invoice)
        GenerateDocumentsJob.perform_later(invoice:, notify: should_deliver_email?)
        Integrations::Aggregator::Invoices::CreateJob.perform_later(invoice:) if invoice.should_sync_invoice?
        Integrations::Aggregator::Invoices::Hubspot::CreateJob.perform_later(invoice:) if invoice.should_sync_hubspot_invoice?
        Invoices::Payments::CreateService.call_async(invoice:) unless skip_psp
      end

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

    attr_accessor :timestamp, :currency, :customer, :fees, :invoice, :skip_psp, :voided_invoice_id

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
      fees_result = Fees::OneOffService.new(invoice:, fees:).call
      fees_result.raise_if_error! unless tax_error?(fees_result)

      result.fees_taxes = fees_result.fees_taxes

      fees_result
    end

    def should_deliver_email?
      License.premium? && customer.billing_entity.email_settings.include?("invoice.finalized")
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
      !fee_result.success? && fee_result.error.respond_to?(:code) && fee_result&.error&.code == "tax_error"
    end
  end
end
