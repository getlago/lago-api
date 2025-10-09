# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::AiConversations::Create, type: :graphql do
  subject(:result) do
    execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: required_permission,
      query:,
      variables: {input: {message: message}}
    )
  end

  let(:query) do
    <<-GQL
      mutation($input: CreateAiConversationInput!) {
        createAiConversation(input: $input) { id name }
      }
    GQL
  end

  let(:required_permission) { "ai_conversations:create" }
  let!(:membership) { create(:membership) }
  let(:message) { Faker::Lorem.word }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "ai_conversations:create"

  it "creates a new AI conversation" do
    expect { result }.to change(AiConversation, :count).by(1)
    expect(result["data"]["createAiConversation"]["name"]).to eq(message)
  end

  it "triggers streaming" do
    expect { result }.to have_enqueued_job(AiConversations::StreamJob).with(
      ai_conversation: kind_of(AiConversation),
      message:
    ).on_queue("default")
  end
end
