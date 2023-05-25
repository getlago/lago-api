# frozen_string_literal: true

class CreditNotesTax < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :credit_note
  belongs_to :tax
end
