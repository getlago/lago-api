# frozen_string_literal: true

module Resolvers
  class AiConversationResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "ai_conversations:view"

    description "Query a single ai conversation of an organization"

    argument :id, ID, required: true, description: "Uniq ID of the ai conversation"

    type Types::AiConversations::Object, null: true

    def resolve(id: nil)
      current_organization.ai_conversations.find(id)
    rescue ActiveRecord::RecordNotFound
      not_found_error(resource: "ai_conversation")
    end
  end
end
