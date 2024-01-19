# frozen_string_literal: true

class AdjustedFee < ApplicationRecord
  belongs_to :invoice
  belongs_to :subscription
  belongs_to :fee, optional: true
  belongs_to :charge, optional: true
  belongs_to :group, optional: true

  enum fee_type: Fee::FEE_TYPES

  def adjusted_display_name?
    adjusted_units.blank? && adjusted_amount.blank?
  end
end
