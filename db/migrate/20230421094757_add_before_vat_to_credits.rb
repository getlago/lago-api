# frozen_string_literal: true

class AddBeforeVatToCredits < ActiveRecord::Migration[7.0]
  def change
    add_column :credits, :before_vat, :boolean, null: false, default: false
  end
end
