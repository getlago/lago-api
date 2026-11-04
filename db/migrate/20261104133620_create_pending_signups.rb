# frozen_string_literal: true

class CreatePendingSignups < ActiveRecord::Migration[8.1]
  def change
    create_enum :pending_signup_token_status, %w[pending consumed replaced]

    # One row per Step 1 attempt of the self-serve signup, written before any organization exists.
    create_table :pending_signups, id: :uuid do |t|
      t.string :email, null: false
      t.string :normalized_email, null: false
      t.string :mailbox_key, null: false
      t.string :password_digest
      t.string :signup_secret_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :emails_sent_at, array: true, null: false, default: []
      t.datetime :closed_at
      t.datetime :verified_at
      t.references :user, type: :uuid, foreign_key: true
      t.datetime :signup_secret_exchanged_at
      t.timestamps

      t.index :signup_secret_digest, unique: true
      t.index :normalized_email
      t.index %i[mailbox_key created_at]
      t.index :created_at
      t.check_constraint "password_digest IS NOT NULL OR verified_at IS NOT NULL OR closed_at IS NOT NULL",
        name: "check_pending_signups_password_digest"
    end

    create_table :pending_signup_tokens, id: :uuid do |t|
      t.references :pending_signup, type: :uuid, null: false, foreign_key: {on_delete: :cascade}
      t.string :token_digest, null: false
      t.enum :status, enum_type: :pending_signup_token_status, null: false, default: "pending"
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.integer :failed_password_attempts, null: false, default: 0
      t.timestamps

      t.index :token_digest, unique: true
      t.index :pending_signup_id, unique: true, where: "status = 'pending'",
        name: "index_pending_signup_tokens_on_live_pending_signup_id"
      t.index :expires_at
      t.check_constraint "status <> 'consumed' OR consumed_at IS NOT NULL", name: "check_pending_signup_tokens_consumed_at"
    end
  end
end
