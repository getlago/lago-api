# frozen_string_literal: true

module Mutations
  module FinanceAssistant
    class Ask < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "ai_conversations:create"

      graphql_name "AskFinanceAssistant"
      description "Asks the finance assistant a question"

      argument :question, String, required: true
      argument :session_id, ID, required: false

      type Types::FinanceAssistant::Answer

      def resolve(question:, session_id: nil)
        raise unauthorized_error unless License.premium?

        result = ::FinanceAssistant::AskService.call(
          organization: current_organization,
          question:,
          session_id:
        )

        result.success? ? result.answer : result_error(result)
      end
    end
  end
end
