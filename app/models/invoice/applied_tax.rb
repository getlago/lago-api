# frozen_string_literal: true

class Invoice
  class AppliedTax < ApplicationRecord
    self.table_name = 'invoices_taxes'

    include PaperTrailTraceable

    belongs_to :invoice
    belongs_to :tax

    monetize :amount_cents
    validates :amount_cents, numericality: { greater_than_or_equal_to: 0 }
  end
end
