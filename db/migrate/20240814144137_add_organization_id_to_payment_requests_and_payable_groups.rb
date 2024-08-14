# frozen_string_literal: true

class AddOrganizationIdToPaymentRequestsAndPayableGroups < ActiveRecord::Migration[7.1]
  def change
    change_table :payment_requests, bulk: true do |t|
      t.uuid :organization_id
    end

    change_table :payable_groups, bulk: true do |t|
      t.uuid :organization_id
    end

    # NOTE: Set organization_id for existing records based on customer_id
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE payment_requests
          SET organization_id = (
            SELECT organization_id
            FROM customers
            WHERE customers.id = payment_requests.customer_id
          );

          UPDATE payable_groups
          SET organization_id = (
            SELECT organization_id
            FROM customers
            WHERE customers.id = payable_groups.customer_id
          )
        SQL
      end
    end

    change_column_null :payment_requests, :organization_id, false
    change_column_null :payable_groups, :organization_id, false
    add_index :payment_requests, :organization_id
    add_index :payable_groups, :organization_id
    add_foreign_key :payment_requests, :organizations
    add_foreign_key :payable_groups, :organizations
  end
end
