# frozen_string_literal: true

module Types
  module AiConversations
    module ToolCalls
      class StatusEnum < Types::BaseEnum
        graphql_name "AiConversationToolCallStatusEnum"

        AiConversationToolCall::STATUSES.each_value do |status|
          value status
        end
      end
    end
  end
end
