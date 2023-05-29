# frozen_string_literal: true

class CreditNote
  class AppliedTax < ApplicationRecord
    self.table_name = 'credit_notes_taxes'

    include PaperTrailTraceable

    belongs_to :credit_note
    belongs_to :tax
  end
end
