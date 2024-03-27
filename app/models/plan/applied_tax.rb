# frozen_string_literal: true

class Plan
  class AppliedTax < ApplicationRecord
    self.table_name = "plans_taxes"

    include PaperTrailTraceable

    belongs_to :plan
    belongs_to :tax
  end
end
