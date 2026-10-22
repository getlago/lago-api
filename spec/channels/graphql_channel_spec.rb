# frozen_string_literal: true

require "rails_helper"

RSpec.describe GraphqlChannel, :premium, type: :channel do
  let(:membership) { create(:membership, roles: [:admin]) }
  let(:organization) { membership.organization }
  let(:ai_conversation) { create(:ai_conversation, organization:, membership:) }
  let(:conversation_id) { ai_conversation.id }
  let(:current_user) { membership.user }
  let(:auth_error_code) { nil }
  let(:token_expired) { false }
  let(:session_claims) { {login_method: Organizations::AuthenticationMethods::EMAIL_PASSWORD} }

  let(:subscription_query) do
    <<~GQL
      subscription($id: ID!) {
        aiConversationStreamed(id: $id) { chunk done }
      }
    GQL
  end

  let(:last_transmission) { transmissions.last }

  def execute_subscription
    perform :execute, query: subscription_query, variables: {id: conversation_id}
  end

  before do
    ENV["MISTRAL_API_KEY"] = "test_api_key"
    ENV["MISTRAL_AGENT_ID"] = "test_agent_id"

    stub_connection(connection_identifier: SecureRandom.uuid, current_user:, auth_error_code:, token_expired?: token_expired, session_claims:)
  end

  context "with an authenticated user and an organization" do
    before { subscribe(organization_id: organization.id) }

    it "subscribes to the member's own conversation" do
      execute_subscription

      expect(last_transmission["more"]).to be(true)
      expect(last_transmission["result"]["errors"]).to be_nil
      expect(last_transmission["result"]["data"]["aiConversationStreamed"]).to eq("chunk" => nil, "done" => false)
      expect(subscription.streams).not_to be_empty
    end

    context "when access changes while the subscription is open" do
      let(:event) { instance_double(GraphQL::Subscriptions::Event, topic:, context: nil) }
      let(:topic) do
        field = LagoApiSchema.subscription.fields["aiConversationStreamed"]
        arguments = {"id" => conversation_id}
        GraphQL::Subscriptions::Event.new(name: field.name, arguments:, field:, context: LagoApiSchema.null_context).topic
      end
      let(:subscription_id) { subscription.instance_variable_get(:@subscription_ids).first }

      def stream_chunk
        LagoApiSchema.subscriptions.execute_update(subscription_id, event, {chunk: "Hello", done: false})
      end

      before { execute_subscription }

      it "keeps streaming while the member still has access" do
        expect(stream_chunk["data"]["aiConversationStreamed"]).to eq("chunk" => "Hello", "done" => false)
      end

      it "ends the subscription once the member loses ai_conversations:view" do
        MembershipRole.where(membership:).delete_all
        role = create(:role, organization:, permissions: %w[ai_conversations:create])
        create(:membership_role, membership:, role:)

        expect(stream_chunk.nil?).to be(true)
        expect(LagoApiSchema.subscriptions.read_subscription(subscription_id)).to be_nil
      end

      it "ends the subscription once the membership is revoked" do
        membership.update!(status: :revoked, revoked_at: Time.current)

        expect(stream_chunk.nil?).to be(true)
      end
    end

    context "when the conversation belongs to another member of the organization" do
      let(:other_membership) { create(:membership, organization:) }
      let(:conversation_id) { create(:ai_conversation, organization:, membership: other_membership).id }

      it "rejects the subscription" do
        execute_subscription

        expect(last_transmission["more"]).to be(false)
        expect(last_transmission["result"]["errors"].first["message"]).to eq("Resource not found")
        expect(subscription.streams).to be_empty
      end
    end

    context "when the member does not have the ai_conversations:view permission" do
      let(:membership) do
        create(:membership).tap do |membership|
          role = create(:role, organization: membership.organization, permissions: %w[customers:view])
          create(:membership_role, membership:, role:)
        end
      end

      it "rejects the subscription" do
        execute_subscription

        expect(last_transmission["more"]).to be(false)
        expect(last_transmission["result"]["errors"].first["message"]).to eq("Missing permissions")
        expect(subscription.streams).to be_empty
      end
    end

    it "returns the parse error of a malformed query" do
      perform :execute, query: "subscription {"

      expect(last_transmission["more"]).to be(false)
      expect(last_transmission["result"]["errors"].first["message"]).to include("Expected")
    end

    it "refuses queries and mutations" do
      perform :execute, query: "query { currentUser { id } }"

      expect(last_transmission["more"]).to be(false)
      expect(last_transmission["result"]["errors"].first["message"]).to eq("Only subscriptions are supported on this channel")
    end
  end

  context "without an authenticated user" do
    let(:current_user) { nil }

    before { subscribe(organization_id: organization.id) }

    it "rejects the operation as unauthorized before parsing it" do
      allow(GraphQL::Query).to receive(:new).and_call_original

      execute_subscription

      expect(last_transmission["result"]["errors"].first["extensions"]).to eq("status" => 401, "code" => "unauthorized")
      expect(GraphQL::Query).not_to have_received(:new)
      expect(subscription.streams).to be_empty
    end
  end

  context "with a query over the maximum length" do
    before { subscribe(organization_id: organization.id) }

    it "rejects it" do
      perform :execute, query: "subscription { #{"a" * GraphqlController::MAX_QUERY_LENGTH} }"

      expect(last_transmission["result"]["errors"].first["extensions"]).to eq("status" => 413, "code" => "query_is_too_large")
    end
  end

  context "without the Mistral configuration" do
    before do
      ENV["MISTRAL_API_KEY"] = nil
      subscribe(organization_id: organization.id)
    end

    it "rejects the subscription" do
      execute_subscription

      expect(last_transmission["result"]["errors"].first["extensions"]["code"]).to eq("feature_unavailable")
      expect(subscription.streams).to be_empty
    end
  end

  context "when the token expires while the socket is open" do
    let(:token_expired) { true }
    let(:close_calls) { [] }

    before do
      calls = close_calls
      connection.define_singleton_method(:close) { |**options| calls << options }
      subscribe(organization_id: organization.id)
    end

    it "closes the socket so the client reconnects with its renewed token" do
      execute_subscription

      expect(close_calls).to eq([{reason: "token_expired", reconnect: true}])
      expect(transmissions.pluck("result")).to all(be_nil)
      expect(subscription.streams).to be_empty
    end
  end

  context "when the token had expired when the socket opened" do
    let(:current_user) { nil }
    let(:auth_error_code) { "expired_jwt_token" }

    before { subscribe(organization_id: organization.id) }

    it "returns the expired token error" do
      execute_subscription

      expect(last_transmission["more"]).to be(false)
      expect(last_transmission["result"]["errors"].first["extensions"]).to eq("status" => 401, "code" => "expired_jwt_token")
      expect(subscription.streams).to be_empty
    end
  end

  context "with a session whose login method the organization does not allow" do
    let(:membership) { create(:membership, roles: [:admin], organization: create(:organization, authentication_methods: %w[email_password])) }
    let(:session_claims) { {login_method: Organizations::AuthenticationMethods::GOOGLE_OAUTH} }

    before { subscribe(organization_id: organization.id) }

    it "rejects the subscription" do
      execute_subscription

      expect(last_transmission["more"]).to be(false)
      expect(last_transmission["result"]["errors"].first["message"]).to eq("Login method not allowed for this organization")
      expect(subscription.streams).to be_empty
    end
  end

  context "with an SSO session" do
    let(:okta) { Organizations::AuthenticationMethods::OKTA }
    let(:membership) { create(:membership, roles: [:admin], organization: create(:organization, authentication_methods: %w[email_password okta])) }

    before { subscribe(organization_id: organization.id) }

    context "when the organization's own integration authenticated the user" do
      let(:session_claims) { {login_method: okta, sso_organization_id: organization.id, sso_issuer: "https://sso.okta.com"} }

      it "subscribes" do
        execute_subscription

        expect(last_transmission["result"]["errors"]).to be_nil
        expect(subscription.streams).not_to be_empty
      end
    end

    context "when another organization's identity provider authenticated the user" do
      let(:session_claims) { {login_method: okta, sso_organization_id: create(:organization).id, sso_issuer: "https://other.okta.com"} }

      it "rejects the subscription" do
        execute_subscription

        expect(last_transmission["more"]).to be(false)
        expect(last_transmission["result"]["errors"].first["message"]).to eq("Login method not allowed for this organization")
        expect(subscription.streams).to be_empty
      end
    end
  end

  context "with an organization the user is not a member of" do
    before { subscribe(organization_id: create(:organization).id) }

    it "rejects the subscription" do
      execute_subscription

      expect(last_transmission["result"]["errors"]).to be_present
      expect(subscription.streams).to be_empty
    end
  end
end
