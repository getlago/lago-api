# frozen_string_literal: true

module Resolvers
  class AiConversationsResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "ai_conversations:view"

    description "Query the latest AI conversations of current organization"

    argument :limit, Integer, required: false

    type Types::AiConversations::Object.collection_type, null: true

    def resolve(limit: nil)
      membership = current_organization.memberships.find_by(user_id: context[:current_user].id)
      current_organization.ai_conversations.where(membership:).order(created_at: :desc).first(limit)
    end
  end
end
