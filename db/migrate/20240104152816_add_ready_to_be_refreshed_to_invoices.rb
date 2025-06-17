# frozen_string_literal: true

class AddReadyToBeRefreshedToInvoices < ActiveRecord::Migration[7.0]
  def change
    add_column :invoices, :ready_to_be_refreshed, :boolean, default: false, null: false
  end
end
