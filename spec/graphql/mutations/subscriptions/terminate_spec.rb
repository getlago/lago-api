# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Subscriptions::Terminate do
  subject(:result) do
    execute_query(
      query: mutation,
      input: input
    )
  end

  let(:required_permission) { "subscriptions:update" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:subscription) { create(:subscription, organization:) }
  let(:mutation) do
    <<~GQL
      mutation($input: TerminateSubscriptionInput!) {
        terminateSubscription(input: $input) {
          id,
          status,
          terminatedAt,
          onTerminationCreditNote
          onTerminationInvoice
        }
      }
    GQL
  end
  let(:input) { {id: subscription.id} }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "subscriptions:update"

  context "when subscription is incomplete" do
    let(:customer) { create(:customer, organization:) }
    let(:plan) { create(:plan, organization:, pay_in_advance: true) }
    let(:subscription) { create(:subscription, :incomplete, organization:, customer:, plan:) }
    let(:invoice) { create(:invoice, :open, customer:, organization:, invoice_type: :subscription) }
    let(:mutation) do
      <<~GQL
        mutation($input: TerminateSubscriptionInput!) {
          terminateSubscription(input: $input) {
            id,
            status,
            canceledAt,
            cancellationReason
          }
        }
      GQL
    end

    before do
      create(:subscription_activation_rule, subscription:, organization:, status: "pending", timeout_hours: 48)
      create(:invoice_subscription, invoice:, subscription:)
    end

    it "cancels the subscription" do
      result_data = result["data"]["terminateSubscription"]

      expect(result_data["id"]).to eq(subscription.id)
      expect(result_data["status"]).to eq("canceled")
      expect(result_data["canceledAt"]).to be_present
      expect(result_data["cancellationReason"]).to eq("manual")
    end
  end

  context "when plan is pay in advance" do
    let(:subscription) { create(:subscription, organization:, plan: create(:plan, :pay_in_advance)) }

    it "terminates a subscription" do
      result_data = result["data"]["terminateSubscription"]

      expect(result_data["id"]).to eq(subscription.id)
      expect(result_data["status"]).to eq("terminated")
      expect(result_data["terminatedAt"]).to be_present
      expect(result_data["onTerminationCreditNote"]).to eq("credit")
      expect(result_data["onTerminationInvoice"]).to eq("generate")
    end

    context "when on_termination_credit_note is provided" do
      let(:input) { {id: subscription.id, onTerminationCreditNote: "skip"} }

      it "creates a credit note" do
        result_data = result["data"]["terminateSubscription"]

        expect(result_data["id"]).to eq(subscription.id)
        expect(result_data["status"]).to eq("terminated")
        expect(result_data["terminatedAt"]).to be_present
        expect(result_data["onTerminationCreditNote"]).to eq("skip")
        expect(result_data["onTerminationInvoice"]).to eq("generate")
        expect(subscription.reload.on_termination_credit_note).to eq("skip")
      end
    end

    context "when on_termination_invoice is provided" do
      let(:input) { {id: subscription.id, onTerminationInvoice: "skip"} }

      it "sets the invoice behavior" do
        result_data = result["data"]["terminateSubscription"]

        expect(result_data["id"]).to eq(subscription.id)
        expect(result_data["status"]).to eq("terminated")
        expect(result_data["terminatedAt"]).to be_present
        expect(result_data["onTerminationInvoice"]).to eq("skip")
        expect(subscription.reload.on_termination_invoice).to eq("skip")
      end
    end
  end
end
