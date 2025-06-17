# frozen_string_literal: true

class AddInvoiceGracePeriod < ActiveRecord::Migration[7.0]
  def change
    add_column :organizations, :invoice_grace_period, :integer, default: 0, null: false
    add_column :customers, :invoice_grace_period, :integer, default: 0, null: false

    reversible do |dir|
      dir.up do
        safety_assured do
          execute <<-SQL
          ALTER TABLE organizations
            ADD CONSTRAINT check_organizations_on_invoice_grace_period
            CHECK (invoice_grace_period >= 0);
          ALTER TABLE customers
            ADD CONSTRAINT check_customers_on_invoice_grace_period
            CHECK (invoice_grace_period >= 0);
          SQL
        end
      end

      dir.down do
        execute <<-SQL
          ALTER TABLE organizations DROP CONSTRAINT check_organizations_on_invoice_grace_period;
          ALTER TABLE customers DROP CONSTRAINT check_customers_on_invoice_grace_period;
        SQL
      end
    end
  end
end
