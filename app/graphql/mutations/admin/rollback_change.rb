# frozen_string_literal: true

module Mutations
  module Admin
    class RollbackChange < BaseMutation
      include AuthenticableAdminUser

      graphql_name "AdminRollbackChange"
      description "Rollback a single admin audit log entry"

      argument :audit_log_id, ID, required: true
      argument :reason, String, required: true

      type Types::Admin::AuditLogType

      def resolve(audit_log_id:, reason:)
        audit_log = CsAdminAuditLog.find_by(id: audit_log_id)

        result = ::Admin::RollbackService.new(
          actor: current_user,
          audit_log: audit_log,
          reason: reason
        ).call

        result.success? ? result.audit_log : result_error(result)
      end
    end
  end
end
