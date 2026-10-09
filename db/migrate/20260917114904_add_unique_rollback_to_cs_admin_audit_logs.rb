# frozen_string_literal: true

class AddUniqueRollbackToCsAdminAuditLogs < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    add_index :cs_admin_audit_logs, :rollback_of_id,
      unique: true, where: "rollback_of_id IS NOT NULL",
      name: "idx_cs_audit_unique_rollback", algorithm: :concurrently
    remove_index :cs_admin_audit_logs, name: "index_cs_admin_audit_logs_on_rollback_of_id", algorithm: :concurrently
  end

  def down
    add_index :cs_admin_audit_logs, :rollback_of_id, algorithm: :concurrently
    remove_index :cs_admin_audit_logs, name: "idx_cs_audit_unique_rollback", algorithm: :concurrently
  end
end
