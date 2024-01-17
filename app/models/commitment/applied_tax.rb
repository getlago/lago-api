# frozen_string_literal: true

class Commitment
  class AppliedTax < ApplicationRecord
    self.table_name = 'commitments_taxes'

    belongs_to :commitment
    belongs_to :tax
  end
end
