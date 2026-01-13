# frozen_string_literal: true

class MigrateStripePaymentMethods < ActiveRecord::Migration[8.0]
  def up
    safety_assured do
      execute <<~SQL
        INSERT INTO payment_methods (
          id,
          organization_id,
          customer_id,
          payment_provider_id,
          payment_provider_customer_id,
          provider_method_id,
          provider_method_type,
          is_default,
          details,
          created_at,
          updated_at
        )
        SELECT
          gen_random_uuid(),
          ppc.organization_id,
          ppc.customer_id,
          ppc.payment_provider_id,
          ppc.id,
          ppc.settings->>'payment_method_id',
          ppc.settings-> 'provider_payment_methods' ->> 0,
          true, -- Set as default since it's the only one
          jsonb_build_object(
            'provider_customer_id', ppc.provider_customer_id, 
            'from_migration', TRUE),
          NOW(),
          NOW()
        FROM payment_provider_customers ppc
        WHERE ppc.type = 'PaymentProviderCustomers::StripeCustomer'
          AND ppc.settings->>'payment_method_id' IS NOT NULL
          AND ppc.deleted_at IS NULL
          AND NOT EXISTS (
            SELECT 1 FROM payment_methods pm
            WHERE pm.customer_id = ppc.customer_id
              AND pm.payment_provider_customer_id = ppc.id
              AND pm.provider_method_id = ppc.settings->>'payment_method_id'
          );
      SQL
    end
  end

  def down
    safety_assured do
      execute <<-SQL
        DELETE FROM payment_methods pm
        USING payment_provider_customers ppc
        WHERE pm.payment_provider_customer_id = ppc.id
          AND ppc.type = 'PaymentProviderCustomers::StripeCustomer';
      SQL
    end
  end
end
