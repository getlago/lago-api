# frozen_string_literal: true

module Mutations
  module FinanceAssistant
    class Export < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "ai_conversations:view"

      graphql_name "ExportFinanceAssistantResult"
      description "Exports the full result set behind a finance assistant answer as CSV"

      argument :message_id, ID, required: true

      type Types::FinanceAssistant::Export

      def resolve(message_id:)
        raise unauthorized_error unless License.premium?

        result = ::FinanceAssistant::ExportService.call(
          organization: current_organization,
          message_id:
        )

        result.success? ? result.export : result_error(result)
      end
    end
  end
end
