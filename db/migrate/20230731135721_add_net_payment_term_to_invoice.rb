# frozen_string_literal: true

class AddNetPaymentTermToInvoice < ActiveRecord::Migration[7.0]
  def change
    add_column :invoices, :net_payment_term, :integer, default: 0, null: false
    safety_assured do
      reversible do |dir|
        dir.up do
          execute <<-SQL
          ALTER TABLE invoices
            ADD CONSTRAINT check_organizations_on_net_payment_term
            CHECK (net_payment_term >= 0);
          SQL
        end

        dir.down do
          execute <<-SQL
          ALTER TABLE invoices DROP CONSTRAINT check_organizations_on_net_payment_term;
          SQL
        end
      end
    end
  end
end
