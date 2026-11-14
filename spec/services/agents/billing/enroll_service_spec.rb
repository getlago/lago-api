# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::Billing::EnrollService, :premium do
  subject(:result) { described_class.call(storefront:, registration:, plan_code:) }

  let(:organization) { create(:organization, premium_integrations: %w[agent_storefront]) }
  let(:storefront) { create(:agent_storefront_integration, organization:) }
  let(:registration) { create(:agent_registration, storefront:) }
  let(:plan) { create(:plan, organization:, amount_cents: 0, amount_currency: "USD") }
  let(:plan_code) { plan.code }

  before { storefront.update!(plans: [{plan_code: plan.code, minimum_topup_cents: 500, maximum_topup_cents: 10_000}]) }

  it "creates the customer, the subscription and an empty wallet" do
    expect(result).to be_success

    customer = organization.customers.sole
    expect(customer).to have_attributes(
      external_id: "agent_#{registration.id}",
      name: "Agent · #{registration.id}",
      exclude_from_dunning_campaign: true
    )
    expect(result.subscription).to have_attributes(
      customer:, plan:, external_id: "agent_#{registration.id}", billing_time: "calendar", status: "active"
    )
    expect(result.wallet).to have_attributes(
      customer:, code: "agent_credits", currency: "USD", rate_amount: 1, balance_cents: 0,
      paid_top_up_min_amount_cents: 500, paid_top_up_max_amount_cents: 10_000
    )
  end

  it "returns the same records when called again" do
    first = described_class.call(storefront:, registration:, plan_code:)

    expect(result.subscription).to eq(first.subscription)
    expect(result.wallet).to eq(first.wallet)
    expect(organization.customers.count).to eq(1)
  end

  context "when the merchant overrode the plan of the agent's subscription" do
    let(:first) { described_class.call(storefront:, registration:, plan_code:) }

    before { first.subscription.update!(plan: create(:plan, organization:, parent: plan, code: plan.code, amount_cents: 0)) }

    it "still returns the same records" do
      expect(result).to be_success
      expect(result.subscription).to eq(first.subscription)
    end
  end

  context "when the registration is enrolled in another plan of the same currency" do
    let(:other_plan) { create(:plan, organization:, amount_cents: 0, amount_currency: "USD") }
    let(:first) { described_class.call(storefront:, registration:, plan_code: other_plan.code) }

    before do
      storefront.update!(plans: storefront.plans + [{plan_code: other_plan.code, minimum_topup_cents: 100, maximum_topup_cents: 1_000}])
      first.wallet.update!(balance_cents: 1_200, credits_balance: 12)
    end

    it "moves it to the plan, keeps its wallet and applies the plan's top-up limits" do
      expect(result).to be_success
      expect(result.subscription).to have_attributes(plan:, external_id: first.subscription.external_id, status: "active")
      expect(first.subscription.reload).to be_terminated
      expect(result.wallet).to eq(first.wallet)
      expect(result.wallet).to have_attributes(balance_cents: 1_200, paid_top_up_min_amount_cents: 500, paid_top_up_max_amount_cents: 10_000)
    end

    context "when the agent changed plan three times in the hour" do
      before do
        Auth::AttemptsThrottle.store = ActiveSupport::Cache::MemoryStore.new
        first
        [plan, other_plan, plan].each { |next_plan| described_class.call!(storefront:, registration:, plan_code: next_plan.code) }
      end

      it "refuses a fourth change and keeps the subscription" do
        refused = described_class.call(storefront:, registration:, plan_code: other_plan.code)

        expect(refused.error).to be_a(BaseService::MethodNotAllowedFailure)
        expect(refused.error.code).to eq("too_many_requests")
        expect(registration.subscription.reload).to have_attributes(plan:, status: "active")
      end

      it "still answers an enrollment in the current plan" do
        expect(result).to be_success
        expect(result.subscription).to eq(registration.subscription)
      end
    end
  end

  context "when the registration is enrolled in a plan of another currency" do
    let(:eur_plan) { create(:plan, organization:, amount_cents: 0, amount_currency: "EUR") }
    let(:first) { described_class.call(storefront:, registration:, plan_code: eur_plan.code) }

    before do
      storefront.update!(plans: storefront.plans + [{plan_code: eur_plan.code}])
      first
    end

    it "refuses and keeps the subscription" do
      expect(result.error.messages).to eq(plan_code: ["currencies_does_not_match"])
      expect(first.subscription.reload).to be_active
    end
  end

  context "when the merchant terminated the agent's subscription" do
    let(:first) { described_class.call(storefront:, registration:, plan_code:) }

    before { first.subscription.mark_as_terminated! }

    it "enrolls it again on the same wallet" do
      expect(result).to be_success
      expect(result.subscription).not_to eq(first.subscription)
      expect(result.subscription).to have_attributes(plan:, status: "active")
      expect(result.wallet).to eq(first.wallet)
    end
  end

  context "with a plan the storefront does not sell" do
    let(:plan_code) { create(:plan, organization:, amount_cents: 0).code }

    it "refuses" do
      expect(result.error.messages).to eq(plan_code: ["plan_not_sold"])
    end
  end

  context "with a plan that has a subscription fee" do
    let(:plan) { create(:plan, organization:, amount_cents: 2_000, amount_currency: "USD") }

    it "refuses without creating anything" do
      expect(result.error.messages).to eq(plan_code: ["plan_not_usage_only"])
      expect(organization.customers).to be_empty
    end
  end

  context "when the storefront was deleted after the agent signed in" do
    before do
      registration
      storefront.class.find(storefront.id).destroy!
    end

    it "fails with not found" do
      expect(result.error.error_code).to eq("agent_storefront_not_found")
      expect(organization.customers).to be_empty
    end
  end

  context "when the merchant deletes the storefront during the enrollment", transaction: false do
    include_context "with mocked security logger"

    it "refuses the deletion once the enrollment commits" do
      registration

      # The enrollment pauses after creating the wallet, before its transaction commits, while the
      # deletion starts.
      paused = Queue.new
      resume = Queue.new
      allow_any_instance_of(described_class).to receive(:create_wallet).and_wrap_original do |original, *args| # rubocop:disable RSpec/AnyInstance
        wallet = original.call(*args)
        paused << true
        resume.pop
        wallet
      end

      in_thread = lambda do |&block|
        Thread.new { ActiveRecord::Base.connection_pool.with_connection(&block) }
      end

      enrollment = in_thread.call do
        described_class.call(storefront: storefront.class.find(storefront.id), registration: registration.class.find(registration.id), plan_code:)
      end
      paused.pop
      deletion = in_thread.call { Integrations::DestroyService.call(integration: storefront.class.find(storefront.id)) }
      sleep 0.5
      resume << true

      expect(enrollment.value).to be_success
      expect(deletion.value.error.code).to eq("agent_storefront_has_enrolled_agents")
      expect(Agents::Registration.exists?(registration.id)).to be(true)
      expect(Integrations::AgentStorefrontIntegration.exists?(storefront.id)).to be(true)
      expect(enrollment.value.wallet.reload).to be_active
    end
  end
end
