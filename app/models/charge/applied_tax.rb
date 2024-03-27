# frozen_string_literal: true

class Charge
  class AppliedTax < ApplicationRecord
    self.table_name = "charges_taxes"

    belongs_to :charge
    belongs_to :tax
  end
end
