# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::AiConversations::CancelToolCall do
  subject(:result) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      current_membership: membership,
      permissions: required_permission,
      query:,
      variables: {input: {id: tool_call.id}}
    )
  end

  let(:required_permission) { "ai_conversations:create" }
  let(:organization) { create(:organization) }
  let(:membership) { create(:membership, organization:) }
  let(:ai_conversation) { create(:ai_conversation, organization:, membership:) }
  let(:tool_call) { create(:ai_conversation_tool_call, ai_conversation:) }

  let(:query) do
    <<~GQL
      mutation($input: CancelAiConversationToolCallInput!) {
        cancelAiConversationToolCall(input: $input) { id name status arguments }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "ai_conversations:create"

  context "without premium feature" do
    it "returns an error" do
      expect_graphql_error(result:, message: "unauthorized")
      expect(tool_call.reload.status).to eq("pending")
    end
  end

  context "without mistral configuration", :premium do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("MISTRAL_API_KEY").and_return(nil)
    end

    it "returns an error" do
      expect_graphql_error(result:, message: "feature_unavailable")
      expect(tool_call.reload.status).to eq("pending")
    end
  end

  context "with premium feature", :premium do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("MISTRAL_API_KEY").and_return("test_api_key")
      allow(ENV).to receive(:[]).with("MISTRAL_AGENT_ID").and_return("test_agent_id")
      allow(ENV).to receive(:[]).with("LAGO_MCP_SERVER_URL").and_return("http://localhost:3001")
    end

    it "records the member's answer and resumes the conversation" do
      data = result["data"]["cancelAiConversationToolCall"]

      expect(data).to include("id" => tool_call.id, "name" => "create_coupon", "status" => "cancelled")
      expect(tool_call.reload.status).to eq("cancelled")
      expect(AiConversations::ResumeJob).to have_been_enqueued.with(ai_conversation)
    end

    context "when the conversation belongs to another member" do
      let(:ai_conversation) { create(:ai_conversation, organization:, membership: create(:membership, organization:)) }

      it "returns a not found error" do
        expect_not_found(result)
        expect(tool_call.reload.status).to eq("pending")
      end
    end

    context "when the call belongs to another organization" do
      let(:ai_conversation) { create(:ai_conversation) }

      it "returns a not found error" do
        expect_not_found(result)
        expect(tool_call.reload.status).to eq("pending")
      end
    end
  end
end
