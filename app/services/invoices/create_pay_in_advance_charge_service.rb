# frozen_string_literal: true

module Invoices
  class CreatePayInAdvanceChargeService < BaseService
    Result = BaseResult[:invoice, :fees_taxes, :invoice_id]

    def initialize(charge:, event:, timestamp:)
      @charge = charge
      @event = Events::CommonFactory.new_instance(source: event)
      @timestamp = timestamp

      super
    end

    def call
      fee_result = generate_fees
      fees = fee_result.fees
      return result if fees.none?

      ActiveRecord::Base.transaction do
        create_generating_invoice
        fees.each { |f| f.update!(invoice:) }

        invoice.fees_amount_cents = invoice.fees.sum(:amount_cents)
        invoice.sub_total_excluding_taxes_amount_cents = invoice.fees_amount_cents
        Credits::AppliedCouponsService.call(invoice:) if invoice.fees_amount_cents&.positive?

        if tax_error?(fee_result)
          invoice.failed!
          invoice.fees.each { |f| SendWebhookJob.perform_later("fee.created", f) }
          create_error_detail(fee_result.error.messages.dig(:tax_error)&.first)
          Utils::ActivityLog.produce(invoice, "invoice.failed")

          # rubocop:disable Rails/TransactionExitStatement
          return fee_result
          # rubocop:enable Rails/TransactionExitStatement
        end

        Invoices::ComputeAmountsFromFees.call(invoice:, provider_taxes: result.fees_taxes)
        create_credit_note_credit
        create_applied_prepaid_credit if should_create_applied_prepaid_credit?
        Invoices::ApplyInvoiceCustomSectionsService.call(invoice:)

        invoice.payment_status = invoice.total_amount_cents.positive? ? :pending : :succeeded
        Invoices::TransitionToFinalStatusService.call(invoice:)
        invoice.save!
      end

      result.invoice = invoice

      unless invoice.closed?
        Utils::SegmentTrack.invoice_created(invoice)
        deliver_webhooks
        Utils::ActivityLog.produce(invoice, "invoice.created")
        GenerateDocumentsJob.perform_later(invoice:, notify: should_deliver_email?)
        Integrations::Aggregator::Invoices::CreateJob.perform_later(invoice:) if invoice.should_sync_invoice?
        Integrations::Aggregator::Invoices::Hubspot::CreateJob.perform_later(invoice:) if invoice.should_sync_hubspot_invoice?
        Invoices::Payments::CreateService.call_async(invoice:)
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue Sequenced::SequenceError, ActiveRecord::StaleObjectError
      raise
    rescue => e
      result.fail_with_error!(e)
    end

    private

    attr_accessor :timestamp, :charge, :event, :invoice

    delegate :subscription, to: :event
    delegate :customer, to: :subscription

    def create_generating_invoice
      invoice_result = Invoices::CreateGeneratingService.call(
        customer:,
        invoice_type: :subscription,
        currency: customer.currency,
        datetime: Time.zone.at(timestamp),
        charge_in_advance: true,
        invoice_id: result.invoice_id
      ) do |invoice|
        Invoices::CreateInvoiceSubscriptionService
          .call(invoice:, subscriptions: [subscription], timestamp:, invoicing_reason: :in_advance_charge)
          .raise_if_error!
      end
      invoice_result.raise_if_error!

      @invoice = invoice_result.invoice
    end

    def generate_fees
      fee_result = Fees::CreatePayInAdvanceService.call(charge:, event:, estimate: true)
      fee_result.raise_if_error! unless tax_error?(fee_result)

      result.fees_taxes = fee_result.fees_taxes
      result.invoice_id = fee_result.invoice_id

      fee_result
    end

    def deliver_webhooks
      invoice.fees.each { |f| SendWebhookJob.perform_later("fee.created", f) }
      SendWebhookJob.perform_later("invoice.created", invoice)
    end

    def should_deliver_email?
      License.premium? && customer.billing_entity.email_settings.include?("invoice.finalized")
    end

    def wallet
      return @wallet if @wallet

      @wallet = customer.wallets.active.first
    end

    def should_create_applied_prepaid_credit?
      return false unless wallet&.active?
      return false unless invoice.total_amount_cents&.positive?

      wallet.balance.positive?
    end

    def create_credit_note_credit
      credit_result = Credits::CreditNoteService.new(invoice:).call
      credit_result.raise_if_error!

      refresh_amounts(credit_amount_cents: credit_result.credits.sum(&:amount_cents)) if credit_result.credits
    end

    def create_applied_prepaid_credit
      prepaid_credit_result = Credits::AppliedPrepaidCreditService.call(invoice:, wallet:)
      prepaid_credit_result.raise_if_error!

      refresh_amounts(credit_amount_cents: prepaid_credit_result.prepaid_credit_amount_cents)
    end

    def refresh_amounts(credit_amount_cents:)
      invoice.total_amount_cents -= credit_amount_cents
    end

    def tax_error?(result)
      return false unless result.error.is_a?(BaseService::ValidationFailure)

      result.error&.messages&.dig(:tax_error).present?
    end

    def create_error_detail(code)
      error_result = ErrorDetails::CreateService.call(
        owner: invoice,
        organization: invoice.organization,
        params: {
          error_code: :tax_error,
          details: {
            tax_error: code
          }
        }
      )
      error_result.raise_if_error!
    end
  end
end
