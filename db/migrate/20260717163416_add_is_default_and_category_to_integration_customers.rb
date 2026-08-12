# frozen_string_literal: true

class AddIsDefaultAndCategoryToIntegrationCustomers < ActiveRecord::Migration[8.0]
  def change
    create_enum :connection_category, %w[payment tax accounting crm]

    add_column :integration_customers, :is_default, :boolean, default: false, null: false
    add_column :integration_customers, :category, :connection_category
  end
end
