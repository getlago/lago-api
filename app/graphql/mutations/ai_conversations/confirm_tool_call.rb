# frozen_string_literal: true

module Mutations
  module AiConversations
    class ConfirmToolCall < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "ai_conversations:create"

      graphql_name "ConfirmAiConversationToolCall"
      description "Confirms a write the AI agent asked for, so the agent runs it"

      argument :id, ID, required: true

      type Types::AiConversations::ToolCall

      def resolve(id:)
        raise unauthorized_error unless License.premium?
        raise forbidden_error(code: "feature_unavailable") if ENV["MISTRAL_API_KEY"].blank? || ENV["MISTRAL_AGENT_ID"].blank?

        # Only the member who owns the conversation answers for the agent acting on their behalf
        tool_call = current_organization.ai_conversation_tool_calls
          .joins(:ai_conversation)
          .where(ai_conversations: {membership_id: current_membership.id})
          .find_by(id:)

        result = ::AiConversations::DecideToolCallService.call(tool_call:, confirmed: true)
        result.success? ? result.tool_call : result_error(result)
      end
    end
  end
end
