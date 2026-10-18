# frozen_string_literal: true

module Types
  module GraphqlSubscriptions
    class AiConversation < Types::BaseSubscription
      include ExecutionErrorResponder
      include CanRequirePermissions
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "ai_conversations:view"

      argument :id, ID, required: true
      type Types::AiConversations::Stream, null: false

      def subscribe(id:)
        unless current_organization.ai_conversations.exists?(id:, membership: current_membership)
          return not_found_error(resource: "ai_conversation")
        end

        # Return an empty object to keep subscription alive
        {chunk: nil, done: false}
      end

      def update(id:)
        object
      end
    end
  end
end
