# frozen_string_literal: true

class AddSourceToInvoiceSubscriptions < ActiveRecord::Migration[7.0]
  def change
    add_column :invoice_subscriptions, :source, :integer

    safety_assured do
      reversible do |dir|
        dir.up do
          execute <<-SQL
          UPDATE invoice_subscriptions
          SET source = 0;
          SQL
        end
      end

      change_column_null :invoice_subscriptions, :source, false
    end
  end
end
