# frozen_string_literal: true

class AddPaymentProviderCodeToCustomers < ActiveRecord::Migration[7.0]
  def up
    add_column :customers, :payment_provider_code, :string
    safety_assured do
      execute <<-SQL
      UPDATE customers
      SET payment_provider_code = (
        CASE WHEN payment_provider = 'adyen' THEN 'adyen_account_1'
             WHEN payment_provider = 'gocardless' THEN 'gocardless_account_1'
             WHEN payment_provider = 'stripe' THEN 'stripe_account_1'
            END
      )
      SQL
    end
  end

  def down
    remove_column :customers, :payment_provider_code
  end
end
