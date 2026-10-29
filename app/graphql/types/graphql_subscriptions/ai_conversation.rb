# frozen_string_literal: true

module Types
  module GraphqlSubscriptions
    class AiConversation < Types::BaseSubscription
      include ExecutionErrorResponder
      include CanRequirePermissions
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "ai_conversations:view"
      ACCESS_CHECK_INTERVAL = 5.seconds

      # Each socket runs its own update, so the token and access checks below apply per socket.
      broadcastable(false)

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
        # The saved context keeps the state of subscribe time, so the token and access are checked again during the stream.
        # Ending with an error, rather than silently, lets the client show why the answer stopped.
        unsubscribe(execution_error(error: "token_expired", status: 401, code: "token_expired")) if token_expired?
        unsubscribe(forbidden_error(code: "forbidden")) unless still_allowed?

        object
      end

      private

      def token_expired?
        context[:channel].connection.token_expired?
      end

      # Access needs several queries, so it is checked at most every ACCESS_CHECK_INTERVAL, and always on the last chunk.
      def still_allowed?
        checked_at = context[:channel].access_checked_at
        subscription_id = context[:subscription_id]
        return true if !object[:done] && checked_at[subscription_id]&.after?(ACCESS_CHECK_INTERVAL.ago)

        allowed = access_allowed?
        allowed ? checked_at[subscription_id] = Time.current : checked_at.delete(subscription_id)
        allowed
      end

      def access_allowed?
        membership = Membership.active.find_by(id: current_membership.id)
        return false unless membership&.organization&.accessible_by_session?(**context[:session_claims])

        membership.permissions_hash[REQUIRED_PERMISSION]
      end
    end
  end
end
