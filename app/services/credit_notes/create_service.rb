# frozen_string_literal: true

module CreditNotes
  class CreateService < BaseService
    def initialize(invoice:, items_attr:, description:, reason: :other)
      @invoice = invoice
      @items_attr = items_attr
      @reason = reason
      @description = description

      super
    end

    def call
      return result.not_found_failure!(resource: invoice) unless invoice

      ActiveRecord::Base.transaction do
        result.credit_note = CreditNote.create!(
          customer: invoice.customer,
          invoice: invoice,
          issuing_date: issuing_date,
          total_amount_currency: invoice.amount_currency,
          vat_amount_currency: invoice.amount_currency,
          credit_amount_currency: invoice.amount_currency,
          credit_vat_amount_currency: invoice.amount_currency,
          refund_amount_currency: invoice.amount_currency,
          refund_vat_amount_currency: invoice.amount_currency,
          balance_amount_currency: invoice.amount_currency,
          reason: reason,
          description: description,
          credit_status: 'available',
        )

        create_items
        return result unless result.success?

        credit_note.credit_status = 'available' if credit_note.credited?
        credit_note.refund_status = 'pending' if credit_note.refunded?

        credit_note.update!(
          total_amount_cents: credit_note.credit_amount_cents + credit_note.refund_amount_cents,
          vat_amount_cents: credit_note.credit_vat_amount_cents + credit_note.refund_vat_amount_cents,
          balance_amount_cents: credit_note.credit_amount_cents,
        )
      end

      track_credit_note_created
      deliver_webhook
      handle_refund if should_handle_refund?

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_accessor :invoice, :items_attr, :reason, :description

    delegate :credit_note, to: :result
    delegate :customer, to: :invoice

    # NOTE: issuing_date must be in customer time zone (accounting date)
    def issuing_date
      Time.current.in_time_zone(customer.applicable_timezone).to_date
    end

    def create_items
      items_attr.each do |item_attr|
        item = credit_note.items.new(
          fee: invoice.fees.find_by(id: item_attr[:fee_id]),
          credit_amount_cents: item_attr[:credit_amount_cents] || 0,
          credit_amount_currency: invoice.amount_currency,
          refund_amount_cents: item_attr[:refund_amount_cents] || 0,
          refund_amount_currency: invoice.amount_currency,
        )
        break unless valid_item?(item)

        item.save!

        # NOTE: update credit note amounts to allow validation on next item
        credit_note.update!(
          credit_amount_cents: credit_note.credit_amount_cents + item.credit_amount_cents,
          refund_amount_cents: credit_note.refund_amount_cents + item.refund_amount_cents,
        )
        refresh_vat_amounts
      end
    end

    def valid_item?(item)
      CreditNotes::ValidateItemService.new(result, item: item).valid?
    end

    def refresh_vat_amounts
      credit_note.credit_vat_amount_cents = compute_vat_amount(credit_note.credit_amount_cents)
      credit_note.refund_vat_amount_cents = compute_vat_amount(credit_note.refund_amount_cents)
    end

    def compute_vat_amount(total_amount)
      total_amount - total_amount.fdiv(1 + (invoice.vat_rate || 0).fdiv(100))
    end

    def track_credit_note_created
      types = []
      types << 'credit' if credit_note.credited?
      types << 'refund' if credit_note.refunded?

      SegmentTrackJob.perform_later(
        membership_id: CurrentContext.membership,
        event: 'credit_note_created',
        properties: {
          organization_id: credit_note.organization.id,
          credit_note_id: credit_note.id,
          credit_note_type: types.join('_and_'),
        },
      )
    end

    def deliver_webhook
      SendWebhookJob.perform_later(
        'credit_note.created',
        credit_note,
      )
    end

    def should_handle_refund?
      return false unless credit_note.refunded?
      return false unless credit_note.invoice.succeeded?

      invoice_payment.present?
    end

    def invoice_payment
      @invoice_payment ||= credit_note.invoice.payments.order(created_at: :desc).first
    end

    def handle_refund
      # TODO: implement refunds on GoCardless
      case invoice_payment.payment_provider
      when PaymentProviders::StripeProvider
        CreditNotes::Refunds::StripeCreateJob.perform_later(credit_note)
      end
    end
  end
end
