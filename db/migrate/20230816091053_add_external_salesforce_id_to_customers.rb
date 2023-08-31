# frozen_string_literal: true

class AddExternalSalesforceIdToCustomers < ActiveRecord::Migration[7.0]
  def change
    add_column :customers, :external_salesforce_id, :string
  end
end
