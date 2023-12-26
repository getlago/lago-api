# frozen_string_literal: true

class AdjustedFee < ApplicationRecord
  belongs_to :invoice
  belongs_to :subscription
  belongs_to :fee, optional: true
  belongs_to :charge, optional: true

  enum fee_type: Fee::FEE_TYPES
end
