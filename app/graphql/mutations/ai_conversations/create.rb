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
        if ENV["MISTRAL_API_KEY"].blank? || ENV["MISTRAL_AGENT_ID"].blank? || ENV["LAGO_MCP_SERVER_URL"].blank?
          raise forbidden_error(code: "feature_unavailable")
        end

        if conversation_id.blank?
          ai_conversation = current_organization.ai_conversations.create!(
            membership: current_membership,
            name: message,
            busy_at: Time.current
          )
          ::AiConversations::StreamJob.perform_later(ai_conversation:, message:)

          return ai_conversation
        end

        ai_conversation = current_membership.ai_conversations.find_by(id: conversation_id)
        return not_found_error(resource: "ai_conversation") unless ai_conversation

        case claim(ai_conversation)
        when :pending_writes
          raise not_allowed_error(code: "ai_conversation_tool_calls_pending")
        when :stalled_resume
          ::AiConversations::ResumeJob.perform_later(ai_conversation)
          raise not_allowed_error(code: "ai_conversation_busy")
        when :busy
          raise not_allowed_error(code: "ai_conversation_busy")
        end

        ::AiConversations::StreamJob.perform_later(ai_conversation:, message:)

        ai_conversation
      end

      private

      # The model expects the results of its last tool calls before any new message, so the message
      # only gets in when the agent is done. The lock keeps two messages from both getting in.
      def claim(ai_conversation)
        ai_conversation.with_lock do
          next :pending_writes if ai_conversation.tool_calls.unsubmitted.pending.exists?
          next :busy if ai_conversation.busy?

          ai_conversation.update!(busy_at: Time.current)

          # A resume that gave up after its retries: start it again rather than close the conversation for good
          next :stalled_resume if ai_conversation.tool_calls.unsubmitted.exists?

          :claimed
        end
      end
    end
  end
end
