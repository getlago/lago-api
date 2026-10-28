# frozen_string_literal: true

module Resolvers
  class AiConversationsResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "ai_conversations:view"
    DEFAULT_LIMIT = 20
    MAX_LIMIT = 100

    description "Query the latest AI conversations of current organization"

    argument :limit, Integer, required: false

    type Types::AiConversations::Object.collection_type, null: true

    def resolve(limit: DEFAULT_LIMIT)
      raise unauthorized_error unless License.premium?
      raise forbidden_error(code: "feature_unavailable") if ENV["MISTRAL_API_KEY"].blank? || ENV["MISTRAL_AGENT_ID"].blank?

      current_membership.ai_conversations.order(created_at: :desc).limit((limit || DEFAULT_LIMIT).clamp(1, MAX_LIMIT))
    end
  end
end
