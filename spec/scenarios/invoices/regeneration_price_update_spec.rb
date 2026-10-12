# frozen_string_literal: true

require "rails_helper"

describe "Regeneration after a plan or terminated subscription price update", :premium, :with_pdf_generation_stub, type: :request do
  include GraphQLHelper

  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:, currency: "USD") }
  let(:membership) { create(:membership, organization:) }
  let(:plan) { create(:plan, organization:, amount_cents: 0, amount_currency: "USD") }
  let(:metric) { create(:sum_billable_metric, :recurring, organization:) }
  let(:charge) { create(:standard_charge, plan:, billable_metric: metric, prorated: true, properties: {amount: "0"}) }
  let(:initial_override) { {} }
  let(:subscription) { customer.subscriptions.sole }
  let(:terminate) { false }
  let(:invoice) { subscription.invoices.order(created_at: :desc).first }
  let(:query) do
    <<~GQL
      query($id: ID!) {
        invoiceBuildRegenerationPreview(id: $id) {
          totalAmountCents
          fees { id subscription { id } invoiceDisplayName units preciseUnitAmount amountCents }
        }
      }
    GQL
  end
  let(:mutation) do
    <<~GQL
      mutation($input: RegenerateInvoiceInput!) {
        regenerateFromVoided(input: $input) {
          id totalAmountCents status
          fees { units amountCents }
        }
      }
    GQL
  end

  before do
    charge
    travel_to(Time.zone.parse("2026-09-01")) do
      create_subscription({external_customer_id: customer.external_id, external_id: customer.external_id,
                           plan_code: plan.code}.merge(initial_override.present? ? {plan_overrides: initial_override} : {}))
    end
    travel_to(Time.zone.parse("2026-09-30")) do
      create_event({external_subscription_id: subscription.external_id, code: metric.code,
                    timestamp: Time.current.to_i, properties: {metric.field_name => "1"}})
    end
    if terminate
      travel_to(Time.zone.parse("2026-09-30T23:59:59Z")) { terminate_subscription(subscription) }
    else
      travel_to(Time.zone.parse("2026-10-01T12:00:00Z")) { perform_billing }
    end
  end

  shared_examples "a consistent repriced invoice" do
    it "shows and saves the current prorated price without changing the original fee" do
      expect(invoice).to be_finalized
      expect(invoice.total_amount_cents).to eq(0)
      original_fee = invoice.fees.charge.sole
      expect(original_fee.units).to eq(1)
      expect(original_fee.amount_cents).to eq(0)

      travel_to(Time.zone.parse("2026-10-02")) do
        update_price
        preview_result = execute_graphql(current_user: membership.user, current_organization: organization,
          permissions: "invoices:view", query:, variables: {id: invoice.id})
        expect(preview_result["errors"]).to be_nil
        preview = preview_result.dig("data", "invoiceBuildRegenerationPreview")
        expect(preview["totalAmountCents"]).to eq("6668")
        expect(preview["fees"].find { |fee| fee["id"] == original_fee.id }["amountCents"]).to eq("6668")
        expect(original_fee.reload.amount_cents).to eq(0)
        expect(invoice.reload).to be_finalized

        void_invoice(invoice)
        result = execute_graphql(current_user: membership.user, current_organization: organization,
          permissions: "invoices:update", query: mutation, variables: {input: {
            voidedInvoiceId: invoice.id,
            fees: preview["fees"].map do |fee|
              fee.slice("id", "invoiceDisplayName", "units")
                .merge("subscriptionId" => fee["subscription"]["id"], "unitAmountCents" => fee["preciseUnitAmount"])
            end
          }})
        expect(result["errors"]).to be_nil
        regenerated = result.dig("data", "regenerateFromVoided")
        expect(regenerated["status"]).to eq("finalized")
        expect(regenerated["totalAmountCents"]).to eq(preview["totalAmountCents"])
        expect(Invoice.find(regenerated["id"]).fees.charge.sole.amount_cents).to eq(6668)
        expect(original_fee.reload.amount_cents).to eq(0)
      end
    end
  end

  context "when updating the plan and cascading to an existing subscription override" do
    let(:initial_override) { {charges: [{id: charge.id, billable_metric_id: metric.id, charge_model: "standard", properties: {amount: "0"}}]} }

    def update_price
      expect(subscription.plan.parent_id).to eq(plan.id)
      update_plan(plan, {cascade_updates: true, charges: [{id: charge.id, billable_metric_id: metric.id,
                                                           charge_model: "standard", prorated: true, properties: {amount: "2000"}}]})
      expect(subscription.reload.plan.charges.sole.properties["amount"]).to eq("2000")
    end

    include_examples "a consistent repriced invoice"
  end

  context "when applying the first override directly to the terminated subscription" do
    let(:terminate) { true }

    def update_price
      expect(subscription.reload).to be_terminated
      expect(subscription.plan_id).to eq(plan.id)
      update_mutation = <<~GQL
        mutation($input: UpdateSubscriptionInput!) {
          updateSubscription(input: $input) { id }
        }
      GQL
      result = execute_graphql(current_user: membership.user, current_organization: organization,
        permissions: "subscriptions:update", query: update_mutation, variables: {input: {
          id: subscription.id, planOverrides: {charges: [{id: charge.id, billableMetricId: metric.id, properties: {amount: "2000"}}]}
        }})
      expect(result["errors"]).to be_nil
      expect(subscription.reload.plan.charges.sole.parent_id).to eq(charge.id)
    end

    include_examples "a consistent repriced invoice"
  end
end
