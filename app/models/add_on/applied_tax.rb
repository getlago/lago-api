# frozen_string_literal: true

class AddOn
  class AppliedTax < ApplicationRecord
    self.table_name = "add_ons_taxes"

    belongs_to :add_on
    belongs_to :tax
  end
end
