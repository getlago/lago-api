# frozen_string_literal: true

module Types
  module AiConversations
    class Object < Types::BaseObject
      graphql_name "AiConversation"

      field :id, ID, null: false
      field :organization, Types::Organizations::OrganizationType, null: false

      field :mistral_conversation_id, String
      field :messages, [Types::AiConversations::Message]
      field :name, String, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      def messages
        ::AiConversations::FetchMessagesService.call(ai_conversation: object)
      end
    end
  end
end
