# frozen_string_literal: true

class AddNetPaymentTermOnOrganizationAndCustomer < ActiveRecord::Migration[7.0]
  def change
    add_column :organizations, :net_payment_term, :integer, default: 0, null: false
    add_column :customers, :net_payment_term, :integer, default: nil, null: true

    safety_assured do
      reversible do |dir|
        dir.up do
          execute <<-SQL
          ALTER TABLE organizations
            ADD CONSTRAINT check_organizations_on_net_payment_term
            CHECK (net_payment_term >= 0);
          ALTER TABLE customers
            ADD CONSTRAINT check_customers_on_net_payment_term
            CHECK (net_payment_term >= 0);
          SQL
        end

        dir.down do
          execute <<-SQL
          ALTER TABLE organizations DROP CONSTRAINT check_organizations_on_net_payment_term;
          ALTER TABLE customers DROP CONSTRAINT check_customers_on_net_payment_term;
          SQL
        end
      end
    end
  end
end
