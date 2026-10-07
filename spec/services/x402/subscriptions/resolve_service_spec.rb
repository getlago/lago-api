# frozen_string_literal: true

require "rails_helper"

describe X402::Subscriptions::ResolveService do
  subject(:result) { described_class.call(customer:, plan_code:, family: :evm) }

  let(:organization) { create(:organization) }
  let(:agent_address) { "0xf4a43B9cc729c9E4E139CB86808f48e3eD09Dcb2" }
  let(:customer) { create(:customer, organization:, currency: nil, external_id: "x402_#{agent_address}", x402_agent_address: agent_address) }
  let(:plan) { create(:plan, organization:, amount_cents: 0, amount_currency: "USD") }
  let(:plan_code) { plan.code }
  let(:external_id) { "x402_#{agent_address}_#{plan.code}" }

  before { allow(Subscriptions::CreateService).to receive(:call).and_call_original }

  context "without a subscription" do
    it "opens one under the x402 external id" do
      expect(result.subscription).to have_attributes(customer:, plan:, external_id:, status: "active", billing_time: "calendar")
    end

    it "sets the customer currency from the plan" do
      expect { result }.to change { customer.reload.currency }.from(nil).to("USD")
    end
  end

  context "when called from the API" do
    before { allow(CurrentContext).to receive(:source).and_return("api") }

    it "opens the subscription" do
      expect(result.subscription).to have_attributes(external_id:, status: "active")
    end
  end

  context "with an active subscription" do
    let(:subscription) { create(:subscription, customer:, plan:, external_id:) }

    before { subscription }

    it "returns it" do
      expect(result.subscription).to eq(subscription)
    end

    it "does not call Subscriptions::CreateService" do
      result

      expect(Subscriptions::CreateService).not_to have_received(:call)
    end
  end

  context "with a terminated subscription" do
    let(:subscription) { create(:subscription, :terminated, customer:, plan:, external_id:) }

    before { subscription }

    it "opens a new subscription" do
      expect(result.subscription).to have_attributes(external_id:, status: "active")
    end

    it "never resumes the terminated one" do
      expect(result.subscription).not_to eq(subscription)
    end
  end

  context "with an incomplete subscription" do
    before { create(:subscription, :incomplete, customer:, plan:, external_id:) }

    it "returns a validation failure" do
      expect(result.error.messages).to eq(subscription: ["subscription_incomplete"])
    end
  end

  context "with a pending subscription" do
    let(:pending_subscription) { create(:subscription, :pending, customer:, plan:, external_id:) }

    before { pending_subscription }

    it "returns a validation failure" do
      expect(result.error.messages).to eq(base: ["subscription_not_active"])
    end

    context "with the pending subscription on another plan" do
      let(:other_plan) { create(:plan, organization:, amount_cents: 0, amount_currency: "USD") }
      let(:pending_subscription) { create(:subscription, :pending, customer:, plan: other_plan, external_id:) }

      it "leaves its plan unchanged" do
        result

        expect(pending_subscription.reload.plan).to eq(other_plan)
      end
    end
  end

  context "with another customer's active subscription under the same id" do
    let(:other_customer) { create(:customer, organization:) }

    before { create(:subscription, customer: other_customer, plan:, external_id:) }

    it "returns a validation failure" do
      expect(result.error.messages).to eq(external_id: ["value_already_exist"])
    end

    it "opens no subscription" do
      expect { result }.not_to change(Subscription, :count)
    end
  end

  context "with a deleted plan" do
    let(:plan) { create(:plan, organization:, amount_cents: 0, amount_currency: "USD", deleted_at: Time.current) }

    it "returns a not found failure" do
      expect(result.error.error_code).to eq("plan_not_found")
    end
  end

  context "when the activation fails" do
    subject(:result) { ActiveRecord::Base.transaction { described_class.call(customer:, plan_code:, family: :evm) } }

    before do
      allow(Subscriptions::ActivateService).to receive(:call)
        .and_return(BaseService::Result.new.service_failure!(code: "activation_failed", message: "activation failed"))
    end

    it "returns the failure" do
      expect(result.error.code).to eq("activation_failed")
    end

    it "leaves no subscription behind" do
      expect { result }.not_to change(Subscription, :count)
    end

    it "leaves the customer currency unset" do
      expect { result }.not_to change { customer.reload.currency }
    end
  end
end
