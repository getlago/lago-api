# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::EmitFixedChargeEventsService, type: :service do
  subject(:service) { described_class.new(subscriptions:, timestamp:) }

  let(:timestamp) { Time.current }
  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:add_on) { create(:add_on, organization:) }

  let(:fixed_charge_1) { create(:fixed_charge, plan:, add_on:) }
  let(:fixed_charge_2) { create(:fixed_charge, plan:, add_on:) }

  let(:subscription_1) { create(:subscription, :active, plan:) }
  let(:subscription_2) { create(:subscription, :active, plan:) }
  let(:subscriptions) { [subscription_1, subscription_2] }

  let(:fixed_charge_emit_service) { FixedCharges::EmitFixedChargeEventService }

  before do
    fixed_charge_1
    fixed_charge_2
    allow(fixed_charge_emit_service).to receive(:call)
  end

  describe "#call" do
    subject(:result) { service.call }

    it "calls FixedCharges::EmitFixedChargeEventService for each subscription and fixed charge" do
      expect(result).to be_success

      expect(fixed_charge_emit_service).to have_received(:call).exactly(4).times

      expect(fixed_charge_emit_service).to have_received(:call).with(
        subscription: subscription_1,
        fixed_charge: fixed_charge_1,
        timestamp:
      ).once

      expect(fixed_charge_emit_service).to have_received(:call).with(
        subscription: subscription_1,
        fixed_charge: fixed_charge_2,
        timestamp:
      ).once

      expect(fixed_charge_emit_service).to have_received(:call).with(
        subscription: subscription_2,
        fixed_charge: fixed_charge_1,
        timestamp:
      ).once

      expect(fixed_charge_emit_service).to have_received(:call).with(
        subscription: subscription_2,
        fixed_charge: fixed_charge_2,
        timestamp:
      ).once
    end

    context "when subscriptions have no fixed charges" do
      let(:plan_without_fixed_charges) { create(:plan, organization:) }
      let(:subscription_without_fixed_charges) { create(:subscription, :active, plan: plan_without_fixed_charges) }
      let(:subscriptions) { [subscription_without_fixed_charges] }

      it "does not call the emit service" do
        expect(result).to be_success
        expect(fixed_charge_emit_service).not_to have_received(:call)
      end
    end
  end
end
