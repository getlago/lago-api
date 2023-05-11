# frozen_string_literal: true

class AppliedTaxRate < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :customer
  belongs_to :tax_rate
end
