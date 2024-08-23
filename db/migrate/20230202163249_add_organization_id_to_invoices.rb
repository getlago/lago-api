# frozen_string_literal: true

class AddOrganizationIdToInvoices < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      add_reference :invoices, :organization, type: :uuid, foreign_key: true, index: true, null: true

      reversible do |dir|
        dir.up do
          execute <<-SQL
          UPDATE invoices
          SET organization_id = customers.organization_id
          FROM customers
          WHERE customers.id = invoices.customer_id
          SQL
        end
      end

      change_column_null :invoices, :organization_id, false
    end
  end
end
