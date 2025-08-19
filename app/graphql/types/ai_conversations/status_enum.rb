# frozen_string_literal: true

module Types
  module AiConversations
    class StatusEnum < Types::BaseEnum
      AiConversation::STATUS.each do |type|
        value type
      end
    end
  end
end
