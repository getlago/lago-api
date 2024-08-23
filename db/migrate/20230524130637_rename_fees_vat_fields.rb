# frozen_string_literal: true

class RenameFeesVatFields < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      rename_column :fees, :vat_rate, :taxes_rate
      rename_column :fees, :vat_amount_cents, :taxes_amount_cents
      remove_column :fees, :vat_amount_currency, :string
    end
  end
end
