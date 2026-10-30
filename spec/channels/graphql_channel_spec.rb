# frozen_string_literal: true

require "rails_helper"

RSpec.describe GraphqlChannel, :premium, type: :channel do
  let(:membership) { create(:membership, roles: [:admin]) }
  let(:organization) { membership.organization }
  let(:ai_conversation) { create(:ai_conversation, organization:, membership:) }
  let(:conversation_id) { ai_conversation.id }
  let(:current_user) { membership.user }
  let(:token_expired) { false }
  let(:session_claims) { {login_method: Organizations::AuthenticationMethods::EMAIL_PASSWORD} }
  let(:mistral_api_key) { "test_api_key" }

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
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("MISTRAL_API_KEY").and_return(mistral_api_key)
    allow(ENV).to receive(:[]).with("MISTRAL_AGENT_ID").and_return("test_agent_id")

    stub_connection(connection_identifier: SecureRandom.uuid, current_user:, token_expired?: token_expired, session_claims:)
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

      def stream_chunk(done: false)
        LagoApiSchema.subscriptions.execute_update(subscription_id, event, {chunk: "Hello", done:})
      end

      def revoke_membership
        membership.update!(status: :revoked, revoked_at: Time.current)
      end

      def expect_ended_with_error(result, code:, status:)
        expect(result["data"]).to be_nil
        expect(result["errors"].first["extensions"]).to include("code" => code, "status" => status)
        expect(result.context.namespace(:subscriptions)[:final_update]).to be(true)
      end

      before { execute_subscription }

      context "when the answer ends on writes to confirm" do
        let(:subscription_query) do
          <<~GQL
            subscription($id: ID!) {
              aiConversationStreamed(id: $id) { done pendingToolCalls { id name status batchAnswered } }
            }
          GQL
        end

        it "sends every field of the pending calls" do
          tool_call = create(:ai_conversation_tool_call, ai_conversation:)

          result = LagoApiSchema.subscriptions.execute_update(subscription_id, event, {chunk: nil, done: true, pending_tool_calls: [tool_call]})

          expect(result["errors"]).to be_nil
          expect(result["data"]["aiConversationStreamed"]["pendingToolCalls"]).to eq([
            {"id" => tool_call.id, "name" => "create_coupon", "status" => "pending", "batchAnswered" => false}
          ])
        end
      end

      it "keeps streaming while the member still has access" do
        expect(stream_chunk["data"]["aiConversationStreamed"]).to eq("chunk" => "Hello", "done" => false)
      end

      it "ends the subscription with an error once the member loses ai_conversations:view" do
        MembershipRole.where(membership:).delete_all
        role = create(:role, organization:, permissions: %w[ai_conversations:create])
        create(:membership_role, membership:, role:)

        expect_ended_with_error(stream_chunk, code: "forbidden", status: 403)
      end

      it "ends the subscription with an error once the organization no longer allows the session's login method" do
        organization.update!(authentication_methods: [Organizations::AuthenticationMethods::GOOGLE_OAUTH])

        expect_ended_with_error(stream_chunk, code: "forbidden", status: 403)
      end

      it "ends the subscription with an error once the membership is revoked" do
        revoke_membership

        expect_ended_with_error(stream_chunk, code: "forbidden", status: 403)
      end

      it "removes the subscription once its error is delivered" do
        revoke_membership
        result = stream_chunk

        expect(LagoApiSchema.subscriptions.read_subscription(subscription_id)).not_to be_nil
        LagoApiSchema.subscriptions.deliver(subscription_id, result)
        expect(LagoApiSchema.subscriptions.read_subscription(subscription_id)).to be_nil
      end

      it "checks access again only once the interval has passed" do
        stream_chunk
        expect(subscription.access_checked_at.keys).to eq([subscription_id])
        revoke_membership

        expect(stream_chunk["data"]["aiConversationStreamed"]).to eq("chunk" => "Hello", "done" => false)
        travel(6.seconds) { expect_ended_with_error(stream_chunk, code: "forbidden", status: 403) }
      end

      it "checks access on the last chunk" do
        stream_chunk
        revoke_membership

        expect_ended_with_error(stream_chunk(done: true), code: "forbidden", status: 403)
      end

      it "keeps the subscription after delivering a chunk" do
        LagoApiSchema.subscriptions.deliver(subscription_id, stream_chunk)

        expect(LagoApiSchema.subscriptions.read_subscription(subscription_id)).not_to be_nil
      end

      it "removes its subscriptions when the client unsubscribes" do
        unsubscribe

        expect(LagoApiSchema.subscriptions.read_subscription(subscription_id)).to be_nil
      end

      context "when the token expires during the stream" do
        before { allow(subscription.connection).to receive(:token_expired?).and_return(false, true) }

        it "ends the subscription with an error at the next chunk, without waiting for the access check" do
          expect(stream_chunk["data"]["aiConversationStreamed"]).to eq("chunk" => "Hello", "done" => false)
          expect_ended_with_error(stream_chunk, code: "token_expired", status: 401)
        end
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

    it "registers the subscription of each socket on its own" do
      execute_subscription
      stub_connection(connection_identifier: SecureRandom.uuid, current_user:, token_expired?: false, session_claims:)
      subscribe(organization_id: organization.id)
      execute_subscription

      # Updates run once per fingerprint: one per subscription means each socket gets its own token and access checks.
      field = LagoApiSchema.subscription.fields["aiConversationStreamed"]
      topic = GraphQL::Subscriptions::Event.new(name: field.name, arguments: {"id" => conversation_id}, field:, context: LagoApiSchema.null_context).topic
      events_by_fingerprint = LagoApiSchema.subscriptions.instance_variable_get(:@events)[topic]
      expect(events_by_fingerprint.values.map(&:size)).to eq([1, 1])
    end

    it "checks the membership again for each operation on the channel" do
      execute_subscription
      membership.update!(status: :revoked, revoked_at: Time.current)
      execute_subscription

      expect(last_transmission["more"]).to be(false)
      expect(last_transmission["result"]["errors"]).to be_present
    end

    it "returns an error for malformed variables" do
      perform :execute, query: subscription_query, variables: "{bad"

      expect(last_transmission["more"]).to be(false)
      expect(last_transmission["result"]["errors"].first["extensions"]).to eq("status" => 422, "code" => "invalid_variables")
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

  context "with a query over the maximum length" do
    before { subscribe(organization_id: organization.id) }

    it "rejects it" do
      perform :execute, query: "subscription { #{"a" * GraphqlController::MAX_QUERY_LENGTH} }"

      expect(last_transmission["result"]["errors"].first["extensions"]).to eq("status" => 413, "code" => "query_is_too_large")
    end
  end

  context "without the Mistral configuration" do
    let(:mistral_api_key) { nil }

    before { subscribe(organization_id: organization.id) }

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
