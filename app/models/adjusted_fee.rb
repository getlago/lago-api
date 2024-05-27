# frozen_string_literal: true

class AdjustedFee < ApplicationRecord
  belongs_to :invoice
  belongs_to :subscription
  belongs_to :fee, optional: true
  belongs_to :charge, optional: true
  belongs_to :group, optional: true
  belongs_to :charge_filter, optional: true

  ADJUSTED_FEE_TYPES = [
    :adjusted_units,
    :adjusted_amount
  ].freeze

  enum fee_type: Fee::FEE_TYPES

  def adjusted_display_name?
    adjusted_units.blank? && adjusted_amount.blank?
  end
end
