# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::AiConversations::Create do
  let_it_be(:organization) { create_default(:organization) }
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
  let(:message) { Faker::Lorem.word }

  let(:required_permission) { "ai_conversations:create" }

  let_it_be(:membership) { create_default(:membership) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "ai_conversations:create"

  context "without premium feature" do
    it "returns an error" do
      expect_graphql_error(result:, message: "unauthorized")
    end
  end

  context "without mistral configuration", :premium do
    before do
      ENV["MISTRAL_API_KEY"] = nil
      ENV["MISTRAL_AGENT_ID"] = nil
    end

    it "returns an error" do
      expect_graphql_error(result:, message: "feature_unavailable")
    end
  end

  context "with premium feature", :premium do
    before do
      ENV["MISTRAL_API_KEY"] = "test_api_key"
      ENV["MISTRAL_AGENT_ID"] = "test_agent_id"
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("LAGO_MCP_SERVER_URL").and_return(mcp_server_url)
    end

    let(:mcp_server_url) { "http://localhost:3001" }

    context "without an MCP server" do
      let(:mcp_server_url) { nil }

      it "refuses the message before the conversation is created" do
        expect { result }.not_to change(AiConversation, :count)
        expect_graphql_error(result:, message: "feature_unavailable")
      end
    end

    it "creates a new AI conversation, busy until the agent answers" do
      expect { result }.to change(AiConversation, :count).by(1)
      expect(result["data"]["createAiConversation"]["name"]).to eq(message)
      expect(AiConversation.last).to be_busy
    end

    it "triggers streaming" do
      expect { result }.to have_enqueued_job(AiConversations::StreamJob).with(
        ai_conversation: kind_of(AiConversation),
        message:
      ).on_queue("default")
    end

    context "with a conversation id" do
      subject(:result) do
        execute_graphql(
          current_user: membership.user,
          current_organization: membership.organization,
          permissions: required_permission,
          query:,
          variables: {input: {message:, conversationId: ai_conversation.id}}
        )
      end

      context "when the conversation belongs to the current member" do
        let(:ai_conversation) { create(:ai_conversation, organization: membership.organization, membership:) }

        it "appends the message to the conversation" do
          expect { result }.to have_enqueued_job(AiConversations::StreamJob).with(ai_conversation:, message:)
          expect(result["data"]["createAiConversation"]["id"]).to eq(ai_conversation.id)
        end
      end

      context "when the conversation belongs to another member of the organization" do
        let(:other_membership) { create(:membership, organization: membership.organization) }
        let(:ai_conversation) { create(:ai_conversation, organization: membership.organization, membership: other_membership) }

        it "returns a not found error" do
          expect { result }.not_to have_enqueued_job(AiConversations::StreamJob)
          expect_graphql_error(result:, message: "Resource not found")
        end
      end
    end

    context "when a write of the conversation waits for the member's confirmation" do
      subject(:result) do
        execute_graphql(
          current_user: membership.user,
          current_organization: membership.organization,
          permissions: required_permission,
          query:,
          variables: {input: {message:, conversationId: ai_conversation.id}}
        )
      end

      let(:ai_conversation) { create(:ai_conversation, organization: membership.organization, membership:) }

      before { create(:ai_conversation_tool_call, ai_conversation:) }

      it "refuses the message" do
        expect { result }.not_to have_enqueued_job(AiConversations::StreamJob)
        expect_graphql_error(result:, message: "Method Not Allowed")
        expect(result["errors"].first["extensions"]["code"]).to eq("ai_conversation_tool_calls_pending")
      end
    end

    context "when the member answered every write but the results did not reach the model yet" do
      subject(:result) do
        execute_graphql(
          current_user: membership.user,
          current_organization: membership.organization,
          permissions: required_permission,
          query:,
          variables: {input: {message:, conversationId: ai_conversation.id}}
        )
      end

      let(:ai_conversation) { create(:ai_conversation, organization: membership.organization, membership:) }

      before { create(:ai_conversation_tool_call, ai_conversation:, status: "confirmed") }

      it "starts the resume again and refuses the message" do
        expect { result }.not_to have_enqueued_job(AiConversations::StreamJob)
        expect(result["errors"].first["extensions"]["code"]).to eq("ai_conversation_busy")
        expect(AiConversations::ResumeJob).to have_been_enqueued.with(ai_conversation)
        expect(ai_conversation.reload).to be_busy
      end
    end

    context "when the agent is still answering" do
      subject(:result) do
        execute_graphql(
          current_user: membership.user,
          current_organization: membership.organization,
          permissions: required_permission,
          query:,
          variables: {input: {message:, conversationId: ai_conversation.id}}
        )
      end

      let(:ai_conversation) { create(:ai_conversation, organization: membership.organization, membership:, busy_at:) }
      let(:busy_at) { 1.minute.ago }

      it "refuses the message" do
        expect { result }.not_to have_enqueued_job(AiConversations::StreamJob)
        expect(result["errors"].first["extensions"]["code"]).to eq("ai_conversation_busy")
      end

      context "when the answer started too long ago" do
        let(:busy_at) { (AiConversation::BUSY_TIMEOUT + 1.minute).ago }

        it "accepts the message" do
          expect { result }.to have_enqueued_job(AiConversations::StreamJob)
          expect(ai_conversation.reload).to be_busy
        end
      end
    end
  end
end
