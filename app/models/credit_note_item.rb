# frozen_string_literal: true

class CreditNoteItem < ApplicationRecord
  belongs_to :credit_note
  belongs_to :fee

  monetize :amount_cents
  monetize :vat_amount_cents
  monetize :total_amount_cents

  validates :amount_cents, numericality: { greater_than_or_equal_to: 0 }

  def currency
    amount_currency
  end

  def vat_amount_cents
    (amount_cents * (fee.vat_rate || 0)).fdiv(100).ceil
  end
  alias vat_amount_currency currency

  def total_amount_cents
    amount_cents + vat_amount_cents
  end
  alias total_amount_currency currency
end
