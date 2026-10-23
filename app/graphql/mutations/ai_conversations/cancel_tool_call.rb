# frozen_string_literal: true

module Mutations
  module AiConversations
    class CancelToolCall < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "ai_conversations:create"

      graphql_name "CancelAiConversationToolCall"
      description "Cancels a write the AI agent asked for"

      argument :id, ID, required: true

      type Types::AiConversations::ToolCall

      def resolve(id:)
        # Only the member who owns the conversation answers for the agent acting on their behalf
        tool_call = current_organization.ai_conversation_tool_calls
          .joins(:ai_conversation)
          .where(ai_conversations: {membership_id: current_membership.id})
          .find_by(id:)

        result = ::AiConversations::DecideToolCallService.call(tool_call:, confirmed: false)
        result.success? ? result.tool_call : result_error(result)
      end
    end
  end
end
