# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::BillingDocumentService do
  subject(:document) { described_class.call(storefront:).document }

  let(:storefront) { create(:agent_storefront_integration) }
  let(:organization) { storefront.organization }

  context "with sold plans" do
    let(:plan) { create(:plan, organization:, name: "Basic", code: "agent_basic", amount_cents: 0, amount_currency: "EUR", interval: :monthly) }
    let(:billable_metric) { create(:billable_metric, organization:, code: "api_call", name: "API call", description: "One call.") }

    before do
      create(:standard_charge, plan:, billable_metric:, properties: {amount: "0.01"})
      storefront.update!(plans: [{plan_code: plan.code, minimum_topup_cents: 500}])
    end

    context "when a sold plan has a subscription fee" do
      let(:pro_plan) { create(:plan, organization:, name: "Pro", code: "agent_pro", amount_cents: 2_000) }

      before { storefront.update!(plans: storefront.plans + [{plan_code: pro_plan.code}]) }

      it "leaves it out, as enrollment refuses it" do
        expect(document).to include("### Basic (`agent_basic`)")
        expect(document).not_to include("agent_pro")
      end
    end

    it "lists each plan with its top-up limits and actions, then how to enroll" do
      expect(document).to include("### Basic (`agent_basic`)")
      expect(document).to include("Billed monthly, in EUR. Top-ups: at least 500, no maximum.")
      expect(document).to include("- `api_call`: API call. One call. Charge model `standard`, properties `{\"amount\":\"0.01\"}`.")
      expect(document).to include("`purpose: \"authenticate\"` and `scope: \"billing\"`")
      expect(document).to include("POST `#{storefront.agent_url}/billing/enroll`")
    end
  end

  context "without sold plans" do
    it "says so" do
      expect(document).to include("This storefront sells no plans yet.")
    end
  end

  context "when the Stripe connection has a seller profile" do
    before { storefront.stripe_provider.update!(seller_profile: "profile_test_123") }

    it "explains how to pay with a shared payment token" do
      expect(document).to include("## Add credits")
      expect(document).to include("`seller_details[network_business_profile]` set to `profile_test_123`")
      expect(document).to include("POST `#{storefront.agent_url}/billing/payments` with JSON `amount_cents` and `shared_payment_token`")
      expect(document).to include("GET `#{storefront.agent_url}/billing/payments/<id>`")
    end
  end

  context "when the Stripe connection has no seller profile" do
    it "says payments are not accepted yet" do
      expect(document).to include("#{storefront.name} does not accept payments from agents yet.")
      expect(document).not_to include("/billing/payments")
    end
  end
end
