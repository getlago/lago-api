# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::AiConversations::Create, type: :graphql do
  subject(:result) do
    execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: required_permission,
      query:,
      variables: {input: {inputData: "Hello, how are you?"}}
    )
  end

  let(:query) do
    <<-GQL
      mutation($input: CreateAiConversationInput!) {
        createAiConversation(input: $input) { id inputData }
      }
    GQL
  end

  let(:required_permission) { "ai_conversations:create" }
  let!(:membership) { create(:membership) }
  let(:input_data) { Faker::Lorem.word }
  let(:conversation_id) { Faker::Lorem.word }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "ai_conversations:create"

  it "creates a new AI conversation" do
    expect { result }.to change(AiConversation, :count).by(1)
  end

  it "creates an AiConversation and triggers streaming" do
    result

    json = JSON.parse(response.body)
    data = json.dig("data", "createAiConversation")

    expect(data["conversationId"]).to eq(conversation_id)
    expect(data["inputData"]).to eq("")
  end

  it "triggers subscription broadcasting" do
    allow(LagoApiSchema.subscriptions).to receive(:trigger)

    post "/graphql", params: {
      query: query,
      variables: {
        prompt: prompt,
        conversationId: conversation_id
      }
    }

    # Wait briefly to allow the background thread to start
    sleep 0.1

    expect(LagoApiSchema.subscriptions).to have_received(:trigger).at_least(:once)
  end
end
