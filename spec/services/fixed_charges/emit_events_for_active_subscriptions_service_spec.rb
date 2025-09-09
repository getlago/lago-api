# frozen_string_literal: true

require "rails_helper"

RSpec.describe FixedCharges::EmitEventsForActiveSubscriptionsService, type: :service do
  subject(:service) { described_class.new(fixed_charge:) }

  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:add_on) { create(:add_on, organization:) }
  let(:fixed_charge) { create(:fixed_charge, plan:, add_on:) }

  let(:customer_1) { create(:customer, organization:) }
  let(:customer_2) { create(:customer, organization:) }
  let(:active_subscription_1) { create(:subscription, :active, plan:, customer: customer_1) }
  let(:active_subscription_2) { create(:subscription, :active, plan:, customer: customer_2) }
  let(:terminated_subscription) { create(:subscription, :terminated, plan:, customer: customer_1) }

  describe "#call" do
    subject(:result) { service.call }

    before do
      active_subscription_1
      active_subscription_2
      terminated_subscription
      allow(FixedCharges::EmitFixedChargeEventService).to receive(:call!)
    end

    it "returns success result" do
      expect(result).to be_success
    end

    it "emits fixed charge events for all active subscriptions" do
      result

      expect(FixedCharges::EmitFixedChargeEventService)
        .to have_received(:call!)
        .with(subscription: active_subscription_1, fixed_charge:)
        .once

      expect(FixedCharges::EmitFixedChargeEventService)
        .to have_received(:call!)
        .with(subscription: active_subscription_2, fixed_charge:)
        .once
    end

    it "does not emit events for terminated subscriptions" do
      result

      expect(FixedCharges::EmitFixedChargeEventService)
        .not_to have_received(:call!)
        .with(subscription: terminated_subscription, fixed_charge:)
    end

    context "when there are no active subscriptions" do
      let(:active_subscription_1) { nil }
      let(:active_subscription_2) { nil }

      it "does not emit any events" do
        result

        expect(FixedCharges::EmitFixedChargeEventService).not_to have_received(:call!)
      end

      it "returns success result" do
        expect(result).to be_success
      end
    end
  end
end
