# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::WalletResolver do
  let(:query) do
    <<~GQL
      query($id: ID!) {
        wallet(id: $id) {
          id name status creditsBalance
          metadata { key value }
          recurringTransactionRules {
            transactionName
          }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:wallet) { create(:wallet, :with_recurring_transaction_rules, customer:) }

  before { wallet }

  it "returns a wallet" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:,
      variables: {id: wallet.id}
    )

    wallet_response = result["data"]["wallet"]

    expect(wallet_response).to eq(
      {
        "creditsBalance" => 0.0,
        "id" => wallet.id,
        "name" => wallet.name,
        "metadata" => nil,
        "recurringTransactionRules" => [{"transactionName" => "Recurring Transaction Rule"}],
        "status" => "active"
      }
    )
  end

  context "when wallet has metadata" do
    let(:metadata) { create(:item_metadata, owner: wallet, value: {"key1" => "value_1", "key2" => "value_2"}) }

    before { metadata }

    it "returns wallet with metadata" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:,
        variables: {id: wallet.id}
      )

      wallet_response = result["data"]["wallet"]

      expect(wallet_response).to include(
        "id" => wallet.id,
        "name" => wallet.name,
        "status" => "active",
        "metadata" => [
          {"key" => "key1", "value" => "value_1"},
          {"key" => "key2", "value" => "value_2"}
        ]
      )
    end
  end

  context "without current organization" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        query:,
        variables: {id: wallet.id}
      )

      expect_graphql_error(result:, message: "Missing organization id")
    end
  end

  context "when wallet is not found" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:,
        variables: {id: "foo"}
      )

      expect_graphql_error(result:, message: "Resource not found")
    end
  end

  context "with billing_entity_id field" do
    let(:query) do
      <<~GQL
        query($id: ID!) {
          wallet(id: $id) {
            id
            billingEntityId
          }
        }
      GQL
    end

    context "when the wallet is bound to a billing entity" do
      let(:billing_entity) { create(:billing_entity, organization:) }
      let(:wallet) { create(:wallet, customer:, billing_entity:) }

      it "returns the billing_entity_id" do
        result = execute_graphql(
          current_user: membership.user,
          current_organization: organization,
          query:,
          variables: {id: wallet.id}
        )

        expect(result["data"]["wallet"]["billingEntityId"]).to eq(billing_entity.id)
      end
    end

    context "when the wallet has no billing entity (legacy row)" do
      let(:wallet) { create(:wallet, customer:, billing_entity: nil) }

      it "returns null" do
        result = execute_graphql(
          current_user: membership.user,
          current_organization: organization,
          query:,
          variables: {id: wallet.id}
        )

        expect(result["data"]["wallet"]["billingEntityId"]).to be_nil
      end
    end
  end

  context "with connections" do
    let(:connections_query) do
      <<~GQL
        query($id: ID!) {
          wallet(id: $id) {
            id
            connections { category behavior code }
            recurringTransactionRules {
              connections { category behavior code }
            }
          }
        }
      GQL
    end

    let(:pinned) { create(:gocardless_customer, customer:, organization:, code: "gocardless_eu") }

    before do
      create(:stripe_customer, customer:, organization:, code: "stripe_default", is_default: true)
      create(:billing_object_connection, owner: wallet, organization:, category: "tax", behavior: "skip")
      create(:billing_object_connection, owner: wallet, organization:, category: "payment",
        behavior: "specific", payment_provider_customer: pinned)
    end

    def wallet_connections
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query: connections_query,
        variables: {id: wallet.id}
      )
      result["data"]["wallet"]
    end

    it "returns every category with its behaviour and effective code" do
      connections = wallet_connections["connections"].index_by { it["category"] }

      expect(connections.keys).to match_array(%w[payment tax accounting crm])
      expect(connections["payment"]).to eq({"category" => "payment", "behavior" => "specific", "code" => "gocardless_eu"})
      expect(connections["tax"]).to eq({"category" => "tax", "behavior" => "skip", "code" => nil})
      expect(connections["crm"]).to eq({"category" => "crm", "behavior" => "inherit", "code" => nil})
    end

    it "returns the rule's own routing, inherited from the customer" do
      rule_connections = wallet_connections["recurringTransactionRules"].first["connections"].index_by { it["category"] }

      expect(rule_connections["payment"]).to eq(
        {"category" => "payment", "behavior" => "inherit", "code" => "stripe_default"}
      )
    end
  end
end
