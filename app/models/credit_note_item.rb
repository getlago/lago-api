# frozen_string_literal: true

class CreditNoteItem < ApplicationRecord
  belongs_to :credit_note
  belongs_to :fee
end
