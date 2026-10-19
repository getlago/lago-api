# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::GraphqlSubscriptions::AiConversation do
  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "ai_conversations:view"
end
