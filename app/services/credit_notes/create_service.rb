# frozen_string_literal: true

module CreditNotes
  class CreateService < BaseService
    def initialize(invoice:, items_attr:, reason: :other)
      @invoice = invoice
      @items_attr = items_attr
      @reason = reason

      super
    end

    def call
      return result.not_found_failure!(resource: invoice) unless invoice

      ActiveRecord::Base.transaction do
        result.credit_note = CreditNote.create!(
          customer: invoice.customer,
          invoice: invoice,
          total_amount_currency: invoice.amount_currency,
          credit_amount_currency: invoice.amount_currency,
          refund_amount_currency: invoice.amount_currency,
          balance_amount_currency: invoice.amount_currency,
          reason: reason,
          credit_status: 'available',
        )

        create_items
        return result unless result.success?

        credit_note.credit_status = 'available' if credit_note.credited?
        credit_note.refund_status = 'pending' if credit_note.refunded?
        credit_note.update!(
          total_amount_cents: credit_note.credit_amount_cents + credit_note.refund_amount_cents,
          balance_amount_cents: credit_note.credit_amount_cents,
        )
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_accessor :invoice, :items_attr, :reason

    delegate :credit_note, to: :result

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
      end
    end

    def valid_item?(item)
      CreditNotes::ValidateItemService.new(result, item: item).valid?
    end
  end
end
