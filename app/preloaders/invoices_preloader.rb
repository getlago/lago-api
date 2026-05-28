# frozen_string_literal: true

class InvoicesPreloader < BasePreloader
  SCOPES = %i[
    offset_amount_cents
    refunded_amount_cents
    credited_amount_cents
    has_non_voided_credit_notes
  ]

  private

  def preload_offset_amount_cents
    offset_amounts = CreditNote
      .where(invoice_id: record_ids)
      .finalized
      .group(:invoice_id)
      .sum(:offset_amount_cents)

    cache(records, :offset_amount_cents, offset_amounts)
  end

  def preload_refunded_amount_cents
    refund_amounts = CreditNote
      .where(invoice_id: record_ids)
      .group(:invoice_id)
      .sum(:refund_amount_cents)

    cache(records, :refunded_amount_cents, refund_amounts)
  end

  def preload_credited_amount_cents
    fees = records.flat_map(&:fees)

    credited_amounts = CreditNoteItem
      .where(fee_id: fees)
      .group(:fee_id)
      .sum(:amount_cents)

    cache(fees, :credited_amount_cents, credited_amounts)
  end

  def preload_has_non_voided_credit_notes
    non_voided = CreditNote
      .where(invoice_id: record_ids)
      .where.not(credit_status: :voided)
      .group(:invoice_id)
      .count

    records.each do |record|
      record.preloader_cache[:has_non_voided_credit_notes] = non_voided.has_key?(record.id)
    end
  end
end
