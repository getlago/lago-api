# frozen_string_literal: true

class RenameCreditBeforeVat < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      rename_column :credits, :before_vat, :before_taxes
    end
  end
end
