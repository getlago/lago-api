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
        refusal_code = access_refusal_code
        unsubscribe(forbidden_error(code: refusal_code)) if refusal_code

        object
      end

      private

      def token_expired?
        context[:channel].connection.token_expired?
      end

      # Access needs several queries, so it is checked at most every ACCESS_CHECK_INTERVAL, and always on the last chunk.
      # Nil while access is allowed, else the code that ends the stream.
      def access_refusal_code
        checked_at = context[:channel].access_checked_at
        subscription_id = context[:subscription_id]
        return if !object[:done] && checked_at[subscription_id]&.after?(ACCESS_CHECK_INTERVAL.ago)

        refusal_code = current_refusal_code
        refusal_code ? checked_at.delete(subscription_id) : checked_at[subscription_id] = Time.current
        refusal_code
      end

      # An organization waiting for a payment method gets its own code, so the client can route to the activation screen.
      def current_refusal_code
        membership = Membership.active.find_by(id: current_membership.id)
        organization = membership&.organization

        if !organization&.accessible_by_session?(**context[:session_claims])
          "forbidden"
        elsif organization.awaiting_payment_method?
          "organization_inactive"
        elsif !membership.permissions_hash[REQUIRED_PERMISSION]
          "forbidden"
        end
      end
    end
  end
end
