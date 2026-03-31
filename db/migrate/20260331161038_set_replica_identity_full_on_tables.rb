# frozen_string_literal: true

class SetReplicaIdentityFullOnTables < ActiveRecord::Migration[8.0]
  def up
    safety_assured do
      execute <<~SQL.squish
        ALTER TABLE fees REPLICA IDENTITY FULL;
        ALTER TABLE daily_usages REPLICA IDENTITY FULL;
        ALTER TABLE billable_metrics REPLICA IDENTITY FULL;
        ALTER TABLE charges REPLICA IDENTITY FULL;
        ALTER TABLE invoices REPLICA IDENTITY FULL;
        ALTER TABLE organizations REPLICA IDENTITY FULL;
        ALTER TABLE plans REPLICA IDENTITY FULL;
        ALTER TABLE subscriptions REPLICA IDENTITY FULL;
        ALTER TABLE customers REPLICA IDENTITY FULL;
        ALTER TABLE payments REPLICA IDENTITY FULL;
        ALTER TABLE credit_notes REPLICA IDENTITY FULL;
        ALTER TABLE wallets REPLICA IDENTITY FULL;
        ALTER TABLE wallet_transactions REPLICA IDENTITY FULL;
      SQL
    end
  end

  def down
    safety_assured do
      execute <<~SQL.squish
        ALTER TABLE fees REPLICA IDENTITY DEFAULT;
        ALTER TABLE daily_usages REPLICA IDENTITY DEFAULT;
        ALTER TABLE billable_metrics REPLICA IDENTITY DEFAULT;
        ALTER TABLE charges REPLICA IDENTITY DEFAULT;
        ALTER TABLE invoices REPLICA IDENTITY DEFAULT;
        ALTER TABLE organizations REPLICA IDENTITY DEFAULT;
        ALTER TABLE plans REPLICA IDENTITY DEFAULT;
        ALTER TABLE subscriptions REPLICA IDENTITY DEFAULT;
        ALTER TABLE customers REPLICA IDENTITY DEFAULT;
        ALTER TABLE payments REPLICA IDENTITY DEFAULT;
        ALTER TABLE credit_notes REPLICA IDENTITY DEFAULT;
        ALTER TABLE wallets REPLICA IDENTITY DEFAULT;
        ALTER TABLE wallet_transactions REPLICA IDENTITY DEFAULT;
      SQL
    end
  end
end
