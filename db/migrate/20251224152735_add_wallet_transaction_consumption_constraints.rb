# frozen_string_literal: true

class AddWalletTransactionConsumptionConstraints < ActiveRecord::Migration[8.0]
  def up
    safety_assured do
      execute <<-SQL
        CREATE OR REPLACE FUNCTION check_wallet_transaction_consumption_types()
        RETURNS TRIGGER AS $$
        BEGIN
          -- transaction_type is an integer enum: 0 = inbound, 1 = outbound
          IF (SELECT transaction_type FROM wallet_transactions WHERE id = NEW.inbound_wallet_transaction_id) != 0 THEN
            RAISE EXCEPTION 'inbound_wallet_transaction must be inbound';
          END IF;
          IF (SELECT transaction_type FROM wallet_transactions WHERE id = NEW.outbound_wallet_transaction_id) != 1 THEN
            RAISE EXCEPTION 'outbound_wallet_transaction must be outbound';
          END IF;
          RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;

        CREATE TRIGGER enforce_wallet_transaction_consumption_types
        BEFORE INSERT OR UPDATE ON wallet_transaction_consumptions
        FOR EACH ROW EXECUTE FUNCTION check_wallet_transaction_consumption_types();
      SQL
    end
  end

  def down
    safety_assured do
      execute <<-SQL
        DROP TRIGGER IF EXISTS enforce_wallet_transaction_consumption_types ON wallet_transaction_consumptions;
        DROP FUNCTION IF EXISTS check_wallet_transaction_consumption_types();
      SQL
    end
  end
end
