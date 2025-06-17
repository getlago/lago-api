# frozen_string_literal: true

class AddDefaultToVatRate < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      change_column_default :fees, :vat_rate, from: nil, to: 0.0
      change_column_default :invoices, :vat_rate, from: nil, to: 0.0

      change_column_null :fees, :vat_rate, false, 0.0
      change_column_null :invoices, :vat_rate, false, 0.0
    end
  end
end
