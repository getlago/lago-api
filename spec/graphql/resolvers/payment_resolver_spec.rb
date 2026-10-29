# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::PaymentResolver do
  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
  let(:required_permission) { "payments:view" }
  let(:organization) { membership.organization }
  let(:invoice) { create(:invoice, customer:, organization:, fees_amount_cents: 10) }
  let(:payment) { create(:payment, payable: invoice) }

  let(:query) do
    <<~GQL
      query($id: ID!) {
        payment(id: $id) {
          id createdAt updatedAt
        }
      }
    GQL
  end

  let_it_be(:membership) { create_default(:membership) }
  let_it_be(:customer) { create_default(:customer, organization:) }

  before { payment }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "payments:view"

  it "returns a single payment" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {
        id: payment.id
      }
    )

    data = result["data"]["payment"]

    expect(data["id"]).to eq(payment.id)
    expect(data["createdAt"]).to eq(payment.created_at.iso8601)
    expect(data["updatedAt"]).to eq(payment.updated_at.iso8601)
  end

  context "when the payment settled an x402 credit purchase", :premium do
    let(:organization) { create(:organization, feature_flags: ["x402_payments"]) }
    let(:membership) { create(:membership, organization:) }
    let(:agent_address) { "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359" }
    let(:agent) { create(:customer, organization:, x402_agent_address: agent_address) }
    let(:invoice) { create(:invoice, customer: agent, organization:, total_amount_cents: 100) }
    let(:payment) { create(:payment, :x402_payment, payable: invoice, customer: agent, amount_cents: 100) }
    let(:wallet_transaction) { create(:wallet_transaction, credit_amount: 10) }
    let(:query) do
      <<~GQL
        query($id: ID!) {
          payment(id: $id) {
            paymentType
            customer { x402AgentAddress }
            x402Settlement {
              kind status network asset payerAddress payeeAddress settledAmountCents creditAmount
            }
          }
        }
      GQL
    end

    before do
      create(:x402_settlement, payment:, wallet_transaction:, payer_address: agent_address, customer: agent,
        subscription: create(:subscription, customer: agent, organization:),
        x402_connection: create(:x402_connection, organization:))
    end

    it "returns the settlement and the agent address" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {id: payment.id}
      )

      data = result["data"]["payment"]

      expect(data["paymentType"]).to eq("x402")
      expect(data["customer"]["x402AgentAddress"]).to eq(agent_address)
      expect(data["x402Settlement"]).to eq(
        "kind" => "credit_purchase",
        "status" => "settled",
        "network" => "eip155:84532",
        "asset" => "usdc",
        "payerAddress" => agent_address,
        "payeeAddress" => "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed",
        "settledAmountCents" => "100",
        "creditAmount" => "10.0"
      )
    end

    context "when the organization does not have x402 payments" do
      let(:organization) { create(:organization) }

      it "hides the agent address" do
        result = execute_graphql(
          current_user: membership.user,
          current_organization: organization,
          permissions: required_permission,
          query:,
          variables: {id: payment.id}
        )

        expect(result["data"]["payment"]["customer"]["x402AgentAddress"]).to be_nil
      end
    end
  end

  context "when the payment has no x402 settlement" do
    let(:query) do
      <<~GQL
        query($id: ID!) {
          payment(id: $id) { id x402Settlement { kind } }
        }
      GQL
    end

    it "returns a null settlement" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {id: payment.id}
      )

      expect(result["data"]["payment"]).to eq("id" => payment.id, "x402Settlement" => nil)
    end
  end

  context "when payment is not found" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: invoice.organization,
        permissions: required_permission,
        query:,
        variables: {
          id: "foo"
        }
      )

      expect_graphql_error(result:, message: "Resource not found")
    end
  end
end
