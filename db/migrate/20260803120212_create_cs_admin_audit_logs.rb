# frozen_string_literal: true

class CreateCsAdminAuditLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :cs_admin_audit_logs, id: :uuid do |t|
      t.references :actor_user, type: :uuid, null: false, foreign_key: {to_table: :users}
      t.string :actor_email, null: false
      t.integer :action, null: false
      t.references :organization, type: :uuid, null: false, foreign_key: true
      t.integer :feature_type, null: false
      t.string :feature_key, null: false
      t.boolean :before_value
      t.boolean :after_value, null: false
      t.text :reason, null: false
      t.uuid :batch_id
      t.references :rollback_of, type: :uuid, foreign_key: {to_table: :cs_admin_audit_logs}

      t.timestamps
    end

    add_index :cs_admin_audit_logs, [:organization_id, :created_at], order: {created_at: :desc}, name: "idx_cs_audit_org_created"
    add_index :cs_admin_audit_logs, [:actor_user_id, :created_at], order: {created_at: :desc}, name: "idx_cs_audit_actor_created"
    add_index :cs_admin_audit_logs, [:feature_key, :created_at], order: {created_at: :desc}, name: "idx_cs_audit_feature_created"
    add_index :cs_admin_audit_logs, :batch_id, name: "idx_cs_audit_batch"
  end
end
