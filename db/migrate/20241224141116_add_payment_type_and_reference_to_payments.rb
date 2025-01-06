# frozen_string_literal: true

class AddPaymentTypeAndReferenceToPayments < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    create_enum :payment_type, %w[provider manual]

    safety_assured do
      change_table :payments, bulk: true do |t|
        t.column :payment_type, :enum, enum_type: 'payment_type', null: true
        t.column :reference, :string, default: nil
      end
    end

    # Backfill existing records
    Payment.in_batches(of: 10_000).update_all(payment_type: 'provider') # rubocop:disable Rails/SkipsModelValidations

    safety_assured do
      execute <<~SQL
        ALTER TABLE payments ALTER COLUMN payment_type SET DEFAULT 'provider';
      SQL
      execute <<~SQL
        ALTER TABLE payments ALTER COLUMN payment_type SET NOT NULL;
      SQL
    end

    add_index :payments, :payment_type, algorithm: :concurrently
  end

  def down
    remove_index :payments, column: :payment_type

    change_table :payments, bulk: true do |t|
      t.remove :payment_type
      t.remove :reference
    end

    drop_enum :payment_type
  end
end
