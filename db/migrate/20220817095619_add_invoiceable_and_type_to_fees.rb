# frozen_string_literal: true

class AddInvoiceableAndTypeToFees < ActiveRecord::Migration[7.0]
  def change
    add_column :fees, :fee_type, :integer
    safety_assured do
      add_reference :fees, :invoiceable, type: :uuid, polymorphic: true
    end
  end
end
