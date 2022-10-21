# frozen_string_literal: true

class CreditNoteItem < ApplicationRecord
  belongs_to :credit_note
  belongs_to :fee

  monetize :credit_amount_cents
  monetize :refund_amount_cents
  monetize :total_amount_cents

  validates :credit_amount_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :refund_amount_cents, numericality: { greater_than_or_equal_to: 0 }

  def currency
    credit_amount_currency
  end

  def total_amount_cents
    credit_amount_cents + refund_amount_cents
  end
  alias total_amount_currency currency
end
