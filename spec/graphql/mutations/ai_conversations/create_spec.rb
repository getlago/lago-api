# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::AiConversations::Create, type: :graphql do
  subject(:result) do
    execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: required_permission,
      query:,
      variables: {input: {inputData: input_data}}
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

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "ai_conversations:create"

  it "creates a new AI conversation" do
    expect { result }.to change(AiConversation, :count).by(1)
    expect(result["data"]["createAiConversation"]["inputData"]).to eq(input_data)
  end

  it "triggers streaming" do
    result
    expect(AiConversations::StreamJob).to have_been_enqueued
  end
end
