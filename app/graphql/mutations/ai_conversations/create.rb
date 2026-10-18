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
          current_organization.ai_conversations.find_by(id: conversation_id, membership: current_membership)
        else
          current_organization.ai_conversations.create!(
            membership: current_membership,
            name: message
          )
        end
        return not_found_error(resource: "ai_conversation") unless ai_conversation

        ::AiConversations::StreamJob.perform_later(ai_conversation:, message:)

        ai_conversation
      end
    end
  end
end
