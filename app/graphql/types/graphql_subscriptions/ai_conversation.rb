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
        raise unauthorized_error unless License.premium?
        raise forbidden_error(code: "feature_unavailable") if ENV["MISTRAL_API_KEY"].blank? || ENV["MISTRAL_AGENT_ID"].blank?

        return not_found_error(resource: "ai_conversation") unless current_membership.ai_conversations.exists?(id:)

        # Return an empty object to keep subscription alive
        {chunk: nil, done: false}
      end

      def update(id:)
        object
      end
    end
  end
end
