# frozen_string_literal: true

class ChangeIntegrationCustomerExternalIdNullableOption < ActiveRecord::Migration[7.0]
  def change
    change_column_null :integration_customers, :external_customer_id, null: true
  end
end
