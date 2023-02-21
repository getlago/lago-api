# frozen_string_literal: true

module CreditNotes
  class CreateService < BaseService
    def initialize(invoice:, **args)
      @invoice = invoice
      args = args.with_indifferent_access
      @items_attr = args[:items]
      @reason = args[:reason] || :other
      @description = args[:description]
      @credit_amount_cents = args[:credit_amount_cents] || 0
      @refund_amount_cents = args[:refund_amount_cents] || 0

      @automatic = args.key?(:automatic) ? args[:automatic] : false

      super
    end

    def call
      return result.not_found_failure!(resource: 'invoice') unless invoice
      return result.forbidden_failure! unless should_create_credit_note?
      return result.not_allowed_failure!(code: 'invalid_type_or_status') unless valid_type_or_status?

      ActiveRecord::Base.transaction do
        result.credit_note = CreditNote.create!(
          customer: invoice.customer,
          invoice:,
          issuing_date:,
          total_amount_currency: invoice.amount_currency,
          vat_amount_currency: invoice.amount_currency,
          credit_amount_currency: invoice.amount_currency,
          credit_vat_amount_currency: invoice.amount_currency,
          refund_amount_currency: invoice.amount_currency,
          refund_vat_amount_currency: invoice.amount_currency,
          balance_amount_currency: invoice.amount_currency,
          credit_amount_cents:,
          refund_amount_cents:,
          reason:,
          description:,
          credit_status: 'available',
          status: invoice.status,
        )

        create_items
        return result unless result.success?

        valid_credit_note?
        result.raise_if_error!

        credit_note.credit_status = 'available' if credit_note.credited?
        credit_note.refund_status = 'pending' if credit_note.refunded?

        credit_note.update!(
          total_amount_cents: credit_note.credit_amount_cents + credit_note.refund_amount_cents,
          vat_amount_cents: credit_note.items.sum { |i| i.amount_cents * i.fee.vat_rate }.fdiv(100).round,
          balance_amount_cents: credit_note.credit_amount_cents,
        )
      end

      if credit_note.finalized?
        track_credit_note_created
        deliver_webhook
        handle_refund if should_handle_refund?
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue ArgumentError
      result.single_validation_failure!(field: :reason, error_code: 'value_is_invalid')
    rescue BaseService::ValidationFailure
      result
    end

    private

    attr_accessor :invoice,
                  :items_attr,
                  :reason,
                  :description,
                  :credit_amount_cents,
                  :refund_amount_cents,
                  :automatic

    delegate :credit_note, to: :result
    delegate :customer, to: :invoice

    def should_create_credit_note?
      # NOTE: created from subscription termination
      return true if automatic

      # NOTE: credit note is a premium feature
      License.premium?
    end

    def valid_type_or_status?
      return true if automatic
      return false if invoice.credit?

      !invoice.legacy?
    end

    # NOTE: issuing_date must be in customer time zone (accounting date)
    def issuing_date
      Time.current.in_time_zone(customer.applicable_timezone).to_date
    end

    def create_items
      items_attr.each do |item_attr|
        item = credit_note.items.new(
          fee: invoice.fees.find_by(id: item_attr[:fee_id]),
          amount_cents: item_attr[:amount_cents] || 0,
          amount_currency: invoice.amount_currency,
        )
        break unless valid_item?(item)

        item.save!
        refresh_vat_amounts
      end
    end

    def valid_item?(item)
      CreditNotes::ValidateItemService.new(result, item: item).valid?
    end

    def valid_credit_note?
      CreditNotes::ValidateService.new(result, item: credit_note).valid?
    end

    def refresh_vat_amounts
      credit_note.credit_vat_amount_cents = compute_vat_amount(credit_note.credit_amount_cents)
      credit_note.refund_vat_amount_cents = compute_vat_amount(credit_note.refund_amount_cents)
    end

    def compute_vat_amount(total_amount)
      total_amount - total_amount.fdiv(1 + (invoice.vat_rate || 0).fdiv(100))
    end

    def track_credit_note_created
      types = if credit_note.credited? && credit_note.refunded?
        'both'
      elsif credit_note.credited?
        'credit'
      elsif credit_note.refunded?
        'refund'
      end

      SegmentTrackJob.perform_later(
        membership_id: CurrentContext.membership,
        event: 'credit_note_issued',
        properties: {
          organization_id: credit_note.organization.id,
          credit_note_id: credit_note.id,
          invoice_id: credit_note.invoice_id,
          credit_note_method: types,
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
      case invoice_payment.payment_provider
      when PaymentProviders::StripeProvider
        CreditNotes::Refunds::StripeCreateJob.perform_later(credit_note)
      when PaymentProviders::GocardlessProvider
        CreditNotes::Refunds::GocardlessCreateJob.perform_later(credit_note)
      end
    end
  end
end
