# frozen_string_literal: true

class Invoice
  class AppliedTax < ApplicationRecord
    self.table_name = 'invoices_taxes'

    include PaperTrailTraceable

    belongs_to :invoice
    belongs_to :tax, optional: true

    monetize :amount_cents,
      :fees_amount_cents,
      with_model_currency: :amount_currency

    validates :amount_cents, numericality: {greater_than_or_equal_to: 0}
  end
end
