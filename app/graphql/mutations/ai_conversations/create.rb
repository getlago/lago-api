# frozen_string_literal: true

module Mutations
  module AiConversations
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "ai_conversations:create"

      graphql_name "CreateAiConversation"
      description "Creates an AI conversation and appends a message to it"

      argument :conversation_id, ID, required: false
      argument :message, String, required: true

      type Types::AiConversations::Object

      def resolve(message:, conversation_id: nil)
        raise unauthorized_error unless License.premium?
        raise forbidden_error(code: "feature_unavailable") if ENV["MISTRAL_API_KEY"].blank? || ENV["MISTRAL_AGENT_ID"].blank?

        ai_conversation = if conversation_id.present?
          current_membership.ai_conversations.find_by(id: conversation_id)
        else
          current_organization.ai_conversations.create!(
            membership: current_membership,
            name: message
          )
        end
        return not_found_error(resource: "ai_conversation") unless ai_conversation

        # The model expects the results of its last tool calls before any new message: refused while
        # a write waits for the member, and while the resume sends the results. A resume that gave up
        # after its retries no longer closes the conversation once RESUME_TIMEOUT has passed.
        if ai_conversation.resuming? || ai_conversation.tool_calls.unsubmitted.pending.exists?
          raise not_allowed_error(code: "ai_conversation_tool_calls_pending")
        end

        ::AiConversations::StreamJob.perform_later(ai_conversation:, message:)

        ai_conversation
      end
    end
  end
end
