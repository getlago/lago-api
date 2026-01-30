# frozen_string_literal: true

module Resolvers
  class SecurityLogResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "security_logs:view"

    description "Query a single security log by ID"

    argument :log_id, ID, required: true

    type Types::SecurityLogs::Object, null: true

    def resolve(log_id:)
      raise forbidden_error(code: "feature_unavailable") unless SecurityLogsQuery.available?
      raise forbidden_error(code: "feature_unavailable") unless current_organization.security_logs_enabled?

      # Stub: always not found until the implementation is provided
      not_found_error(resource: "security_log")
    end
  end
end
