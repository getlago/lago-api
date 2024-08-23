# frozen_string_literal: true

class AddCustomerToInvoices < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      add_reference :invoices, :customer, type: :uuid, foreign_key: true, index: true
    end
  end
end
