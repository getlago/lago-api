# frozen_string_literal: true

module Invoices
  class CreatePayInAdvanceChargeService < BaseService
    def initialize(charge:, event:, timestamp:)
      @charge = charge
      @event = event
      @timestamp = timestamp

      super
    end

    def call
      # TODO: prevent generation if no fees will be created
      invoice_result = Invoices::CreateGeneratingService.call(
        customer:,
        invoice_type: :subscription,
        currency: customer.currency,
        datetime: Time.zone.at(timestamp),
        subscriptions_details: [Invoices::CreateGeneratingService::SubscriptionDetails.new(subscription, {}, false)],
      )
      invoice_result.raise_if_error!

      @invoice = invoice_result.invoice

      ActiveRecord::Base.transaction do
        create_fees(invoice)
        raise result.service_failure!(code: 'no_fees', message: 'rollback').raise_if_error! if invoice.fees.count.zero?

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
      SendWebhookJob.perform_later('invoice.created', invoice) if should_deliver_webhook?
      InvoiceMailer.with(invoice:).finalized.deliver_later if should_deliver_email?
      Invoices::Payments::CreateService.new(invoice).call

      result.invoice = invoice
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue ServiceFailure => e
      return Result.new if e.code == 'no_fees'

      raise
    end

    private

    attr_accessor :timestamp, :charge, :event, :invoice

    delegate :subscription, :customer, to: :event

    def create_fees(invoice)
      fee_result = Fees::CreatePayInAdvanceService.call(charge:, event:, invoice:)
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
          invoice_type: invoice.invoice_type,
        },
      )
    end

    # NOTE: accounting date must be in customer timezone
    def issuing_date
      Time.zone.at(timestamp).in_time_zone(customer.applicable_timezone).to_date
    end

    def payment_due_date
      (issuing_date + customer.applicable_net_payment_term.days).to_date
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
