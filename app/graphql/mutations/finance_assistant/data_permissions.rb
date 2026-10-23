# frozen_string_literal: true

module Mutations
  module FinanceAssistant
    # The finance assistant reads the organization's billing data with SQL, so the member
    # needs every view permission that data is shown under in the dashboard.
    module DataPermissions
      private

      def ensure_data_permissions!
        missing = ::AiConversations::ToolPolicy::FINANCE_ASSISTANT_PERMISSIONS.reject do |permission|
          context.dig(:permissions, permission)
        end
        return if missing.empty?

        raise GraphQL::ExecutionError.new(
          "Missing permissions",
          extensions: {status: :forbidden, code: "forbidden", required_permissions: missing}
        )
      end
    end
  end
end
