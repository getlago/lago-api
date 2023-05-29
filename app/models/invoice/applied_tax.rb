# frozen_string_literal: true

class Invoice
  class AppliedTax < ApplicationRecord
    self.table_name = 'invoices_taxes'

    include PaperTrailTraceable

    belongs_to :invoice
    belongs_to :tax
  end
end
