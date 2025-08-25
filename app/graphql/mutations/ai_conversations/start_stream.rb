# frozen_string_literal: true

module Mutations
  module AiConversations
    class StartStream < BaseMutation
      argument :conversation_id, ID, required: true
      field :ok, Boolean, null: false

      def resolve(conversation_id:)
        AiConversations::StreamJob.perform_later(conversation_id)
        { ok: true }
      end
    end
  end
end