# frozen_string_literal: true

class NotNullOrganizationIdOnIntegrationCustomers < ActiveRecord::Migration[8.0]
  def up
    validate_check_constraint :integration_customers, name: "integration_customers_organization_id_not_null"
    change_column_null :integration_customers, :organization_id, false
    remove_check_constraint :integration_customers, name: "integration_customers_organization_id_not_null"
  end

  def down
    add_check_constraint :integration_customers, "organization_id IS NOT NULL", name: "integration_customers_organization_id_not_null", validate: false
    change_column_null :integration_customers, :organization_id, true
  end
end
