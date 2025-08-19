# frozen_string_literal: true

module Types
  module AiConversations
    class CreateInput < Types::BaseInputObject
      description "Create Ai Conversation Input"

      argument :input_data, String, required: true
    end
  end
end
