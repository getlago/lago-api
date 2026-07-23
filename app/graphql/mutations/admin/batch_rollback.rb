# frozen_string_literal: true

module Mutations
  module Admin
    class BatchRollback < BaseMutation
      include AuthenticableAdminUser

      graphql_name "AdminBatchRollback"
      description "Rollback all changes in a batch"

      argument :batch_id, ID, required: true
      argument :reason, String, required: true

      type [Types::Admin::AuditLogType]

      def resolve(batch_id:, reason:)
        audit_logs = CsAdminAuditLog.where(batch_id: batch_id).where.not(action: :rollback)
        rollback_logs = []

        audit_logs.find_each do |audit_log|
          result = ::Admin::RollbackService.new(
            actor: current_user,
            audit_log: audit_log,
            reason: "Batch rollback: #{reason}"
          ).call

          return result_error(result) unless result.success?

          rollback_logs << result.audit_log
        end

        rollback_logs
      end
    end
  end
end
