# frozen_string_literal: true

class FulfillAdjustedFeeUnitPreciseAmountCents < ActiveRecord::Migration[7.1]
  class AdjustedFee < ApplicationRecord
    belongs_to :invoice
  end

  class Invoice < ApplicationRecord
    enum status: {draft: 0}
  end

  def change
    AdjustedFee.joins(:invoice).where(invoice: {status: 'draft'}).where(unit_precise_amount_cents: 0).each do |af|
      af.update_attribute(:unit_precise_amount_cents, af.unit_amount_cents.to_f)
    end
  end
end
