# frozen_string_literal: true

module Invoices
  class CreatePayInAdvanceChargeService < BaseService
    def initialize(charge:, event:, timestamp:, invoice: nil)
      @charge = charge
      @event = event
      @timestamp = timestamp

      # NOTE: In case of retry when the creation process failed,
      #       and if the generating invoice was persisted,
      #       the process can be retried without creating a new invoice
      @invoice = invoice

      super
    end

    def call
      fees = generate_fees
      return Result.new if fees.none?

      create_generating_invoice unless invoice
      result.invoice = invoice

      ActiveRecord::Base.transaction do
        fees.each { |f| f.update!(invoice:) }

        invoice.fees_amount_cents = invoice.fees.sum(:amount_cents)
        invoice.sub_total_excluding_taxes_amount_cents = invoice.fees_amount_cents
        Credits::AppliedCouponsService.call(invoice:) if invoice.fees_amount_cents&.positive?

        Invoices::ComputeAmountsFromFees.call(invoice:)
        create_credit_note_credit if credit_notes.any?
        create_applied_prepaid_credit if should_create_applied_prepaid_credit?

        invoice.payment_status = invoice.total_amount_cents.positive? ? :pending : :succeeded
        invoice.finalized!
      end

      track_invoice_created(invoice)

      deliver_webhooks if should_deliver_webhook?
      InvoiceMailer.with(invoice:).finalized.deliver_later if should_deliver_email?
      Integrations::Aggregator::Invoices::CreateJob.perform_later(invoice:) if invoice.should_sync_invoice?
      Integrations::Aggregator::SalesOrders::CreateJob.perform_later(invoice:) if invoice.should_sync_sales_order?
      Invoices::Payments::CreateService.new(invoice).call

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue Sequenced::SequenceError
      raise
    rescue => e
      result.fail_with_error!(e)
    end

    private

    attr_accessor :timestamp, :charge, :event, :invoice

    delegate :subscription, :customer, to: :event

    def create_generating_invoice
      invoice_result = Invoices::CreateGeneratingService.call(
        customer:,
        invoice_type: :subscription,
        currency: customer.currency,
        datetime: Time.zone.at(timestamp),
        charge_in_advance: true,
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
      fee_result.raise_if_error!
      fee_result.fees
    end

    def should_deliver_webhook?
      customer.organization.webhook_endpoints.any?
    end

    def deliver_webhooks
      invoice.fees.each { |f| SendWebhookJob.perform_later('fee.created', f) }
      SendWebhookJob.perform_later('invoice.created', invoice)
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

    def credit_notes
      @credit_notes ||= customer.credit_notes
        .finalized
        .available
        .where.not(invoice_id: invoice.id)
        .order(created_at: :asc)
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
      credit_result = Credits::CreditNoteService.new(invoice:, credit_notes:).call
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
  end
end
