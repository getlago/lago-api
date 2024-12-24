# frozen_string_literal: true

class AddPaymentTypeAndReferenceToPayments < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    create_enum :payment_type, %w[provider manual]

    add_column :payments, :payment_type, :enum, enum_type: 'payment_type', null: true
    add_column :payments, :reference, :string, default: nil

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
  end

  def down
    remove_column :payments, :payment_type
    remove_column :payments, :reference
    drop_enum :payment_type
  end
end
