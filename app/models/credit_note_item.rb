# frozen_string_literal: true

class CreditNoteItem < ApplicationRecord
  belongs_to :credit_note
  belongs_to :fee

  monetize :amount_cents

  validates :amount_cents, numericality: { greater_than_or_equal_to: 0 }
end
