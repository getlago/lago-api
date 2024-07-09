# frozen_string_literal: true

class Fee
  class AppliedTax < ApplicationRecord
    self.table_name = 'fees_taxes'

    include PaperTrailTraceable

    belongs_to :fee
    belongs_to :tax, optional: true
  end
end
