# frozen_string_literal: true

class RenameCustomerIdToExternalIdOnCustomers < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      rename_column :customers, :customer_id, :external_id
    end
  end
end
