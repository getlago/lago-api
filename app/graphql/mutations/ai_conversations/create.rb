# frozen_string_literal: true

module Mutations
  module AiConversations
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "ai_conversations:create"

      graphql_name "CreateAiConversation"
      description "Creates a new AI conversation"

      argument :input_data, String, required: true

      type Types::AiConversations::Object

      def resolve(input_data:)
        membership = current_organization.memberships.find_by(user_id: context[:current_user].id)

        ai_conversation = current_organization.ai_conversations.find_or_create_by!(
          conversation_id: SecureRandom.uuid,
          status: :pending,
          membership:,
          input_data:
        )
      
        ::AiConversations::StreamJob.perform_later(ai_conversation.id)
      
        ai_conversation
      end
    end
  end
end
