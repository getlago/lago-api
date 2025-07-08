# frozen_string_literal: true

class NotNullOrganizationIdOnInvoiceSubscriptions < ActiveRecord::Migration[8.0]
  def up
    validate_check_constraint :invoice_subscriptions, name: "invoice_subscriptions_organization_id_null"
    change_column_null :invoice_subscriptions, :organization_id, false
    remove_check_constraint :invoice_subscriptions, name: "invoice_subscriptions_organization_id_null"
  end

  def down
    add_check_constraint :invoice_subscriptions, "organization_id IS NOT NULL", name: "invoice_subscriptions_organization_id_null", validate: false
    change_column_null :invoice_subscriptions, :organization_id, true
  end
end
