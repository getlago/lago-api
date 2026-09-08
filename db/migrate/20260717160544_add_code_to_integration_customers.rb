# frozen_string_literal: true

class AddCodeToIntegrationCustomers < ActiveRecord::Migration[8.0]
  def change
    add_column :integration_customers, :code, :string
  end
end
