# frozen_string_literal: true

class CreditNote
  class AppliedTax < ApplicationRecord
    self.table_name = "credit_notes_taxes"

    include PaperTrailTraceable

    belongs_to :credit_note
    belongs_to :tax

    monetize :amount_cents
    monetize :base_amount_cents, with_model_currency: :amount_currency
  end
end
