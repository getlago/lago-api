# frozen_string_literal: true

class Customer
  class AppliedTax < ApplicationRecord
    self.table_name = "customers_taxes"

    include PaperTrailTraceable

    belongs_to :customer
    belongs_to :tax
  end
end
