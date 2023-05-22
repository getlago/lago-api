# frozen_string_literal: true

class AppliedTax < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :customer
  belongs_to :tax
end
