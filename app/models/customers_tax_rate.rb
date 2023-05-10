# frozen_string_literal: true

class CustomersTaxRate < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :customer
  belongs_to :tax_rate
end
