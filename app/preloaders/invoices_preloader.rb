# frozen_string_literal: true

class InvoicesPreloader < BasePreloader
  PRELOAD = %i[
    offset_amount_cents
    refunded_amount_cents
    credited_amount_cents
  ]

  private

  def preload_offset_amount_cents
    offset_amounts = CreditNote
      .where(invoice_id: scope_ids)
      .finalized
      .group(:invoice_id)
      .sum(:offset_amount_cents)

    cache(scope, :offset_amount_cents, offset_amounts)
  end

  def preload_refunded_amount_cents
    refund_amounts = CreditNote
      .where(invoice_id: scope_ids)
      .group(:invoice_id)
      .sum(:refund_amount_cents)

    cache(scope, :refunded_amount_cents, refund_amounts)
  end

  def preload_credited_amount_cents
    fees = scope.map(&:fees).flatten

    credited_amounts = CreditNoteItem
      .where(fee_id: fees)
      .group(:fee_id)
      .sum(:amount_cents)

    cache(fees, :credited_amount_cents, credited_amounts)
  end
end
