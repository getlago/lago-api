# frozen_string_literal: true

class CreateSubscriptionActivationRules < ActiveRecord::Migration[8.0]
  def change
    create_table :subscription_activation_rules, id: :uuid do |t|
      t.references :subscription, null: false, foreign_key: true, type: :uuid, index: true
      t.references :organization, null: false, foreign_key: true, type: :uuid

      t.string :rule_type, null: false
      t.string :status, null: false, default: "pending"
      t.integer :timeout_hours
      t.datetime :expires_at

      t.timestamps
    end

    add_index :subscription_activation_rules, [:subscription_id, :rule_type], unique: true,
      name: "index_activation_rules_on_subscription_and_type"
    add_index :subscription_activation_rules, [:status, :expires_at],
      where: "status IN ('pending', 'failed') AND expires_at IS NOT NULL",
      name: "index_activation_rules_pending_with_expiry"
  end
end
