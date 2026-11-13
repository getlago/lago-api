# frozen_string_literal: true

module Mutations
  module FinanceAssistant
    # The finance assistant reads the organization's billing data with SQL, so the member
    # needs every view permission that data is shown under in the dashboard.
    module DataPermissions
      PERMISSIONS = %w[
        analytics:view
        coupons:view
        credit_notes:view
        customers:view
        invoices:view
        payments:view
        plans:view
        subscriptions:view
      ].freeze

      private

      def ensure_data_permissions!
        missing = PERMISSIONS.reject { |permission| context.dig(:permissions, permission) }
        return if missing.empty?

        raise GraphQL::ExecutionError.new(
          "Missing permissions",
          extensions: {status: :forbidden, code: "forbidden", required_permissions: missing}
        )
      end
    end
  end
end
