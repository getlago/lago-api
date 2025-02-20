# frozen_string_literal: true

class AddUniqueIndexToProviderPaymentId < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    safety_assured do
      execute <<-SQL
        UPDATE invoices i
        SET total_paid_amount_cents = total_amount_cents
        WHERE total_paid_amount_cents > total_amount_cents;

        DELETE FROM payments p1
        USING payments p2
        WHERE p1.payment_provider_id = p2.payment_provider_id
        AND p1.provider_payment_id = p2.provider_payment_id
        AND p1.created_at > p2.created_at;
      SQL

      add_index :payments,
        %i[provider_payment_id payment_provider_id],
        unique: true,
        where: "provider_payment_id IS NOT NULL",
        algorithm: :concurrently
    end
  end

  def down
    safety_assured do
      remove_index :payments, %i[provider_payment_id payment_provider_id]
    end
  end
end
