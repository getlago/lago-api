# frozen_string_literal: true

class AddCodeAndNameToPaymentProviders < ActiveRecord::Migration[7.0]
  def up
    safety_assured do
      change_table :payment_providers, bulk: true do |t|
        t.column :code, :string
        t.column :name, :string
      end

      execute <<-SQL
      UPDATE payment_providers
      SET
        name = (
          CASE WHEN type = 'PaymentProviders::AdyenProvider' THEN 'Adyen Account 1'
               WHEN type = 'PaymentProviders::GocardlessProvider' THEN 'GoCardless Account 1'
               WHEN type = 'PaymentProviders::StripeProvider' THEN 'Stripe Account 1'
               END
        ),
        code = (
          CASE WHEN type = 'PaymentProviders::AdyenProvider' THEN 'adyen_account_1'
               WHEN type = 'PaymentProviders::GocardlessProvider' THEN 'gocardless_account_1'
               WHEN type = 'PaymentProviders::StripeProvider' THEN 'stripe_account_1'
               END
        )
      SQL

      change_column_null :payment_providers, :code, false
      change_column_null :payment_providers, :name, false
      add_index :payment_providers, %i[code organization_id], unique: true
    end
  end

  def down
    remove_columns :payment_providers, :code, :name
  end
end
