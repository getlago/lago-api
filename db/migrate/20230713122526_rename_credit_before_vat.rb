# frozen_string_literal: true

class RenameCreditBeforeVat < ActiveRecord::Migration[7.0]
  def change
    rename_column :credits, :before_vat, :before_taxes
  end
end
