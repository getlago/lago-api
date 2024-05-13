# frozen_string_literal: true

class CreditNoteItem < ApplicationRecord
  belongs_to :credit_note
  belongs_to :fee

  monetize :amount_cents

  validates :amount_cents, numericality: {greater_than_or_equal_to: 0}

  def applied_taxes
    credit_note.applied_taxes.where(tax_id: fee.applied_taxes.select('fees_taxes.tax_id'))
  end
end
