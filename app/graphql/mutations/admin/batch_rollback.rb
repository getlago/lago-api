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
        audit_logs = CsAdminAuditLog
          .where(batch_id: batch_id, feature_type: CsAdminAuditLog::TOGGLEABLE_FEATURE_TYPES)
          .where.not(action: :rollback)
        rollback_logs = []
        error = nil

        ActiveRecord::Base.transaction do
          audit_logs.find_each do |audit_log|
            result = ::Admin::RollbackService.call(
              actor: current_user,
              audit_log: audit_log,
              reason: "Batch rollback: #{reason}"
            )

            unless result.success?
              error = result_error(result)
              raise ActiveRecord::Rollback
            end

            rollback_logs << result.audit_log
          end
        end

        error || rollback_logs
      end
    end
  end
end
