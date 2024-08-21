# frozen_string_literal: true

class CreateInvoicesPaymentRequests < ActiveRecord::Migration[7.1]
  def change
    create_table :invoices_payment_requests, id: :uuid do |t|
      t.references :invoice, type: :uuid, null: false, foreign_key: true
      t.references :payment_request, type: :uuid, null: false, foreign_key: true
      t.timestamps
    end

    add_index :invoices_payment_requests, %i[invoice_id payment_request_id], unique: true

    remove_column :payments, :payment_request_id, :uuid

    drop_table :payable_groups do |t|
      t.references :customer, type: :uuid, null: false, foreign_key: true
      t.references :organization, type: :uuid, null: false, foreign_key: true
      t.integer :payment_status, null: false, default: 0
      t.timestamps
    end

    change_table :payment_requests, bulk: true do |t|
      t.remove :payment_requestable_id, type: :uuid
      t.remove :payment_requestable_type, type: :string

      t.integer :payment_status, null: false, default: 0
    end

    # NOTE: Migrate existing data from invoices to invoices_payment_requests
    reversible do |dir|
      dir.up do
        execute <<-SQL
          INSERT INTO invoices_payment_requests (invoice_id, payment_request_id, created_at, updated_at)
          SELECT id, payable_group_id, created_at, updated_at
          FROM invoices
          WHERE payable_group_id IS NOT NULL
        SQL
      end
    end

    remove_column :invoices, :payable_group_id, :uuid
  end
end
