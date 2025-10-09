# frozen_string_literal: true

require "rails_helper"

RSpec.describe FixedCharges::EmitEventsForActiveSubscriptionsService, type: :service do
  subject(:service) { described_class.new(fixed_charge:, subscription:) }

  let(:subscription) { nil }

  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:, interval: :yearly, bill_fixed_charges_monthly: true) }
  let(:add_on) { create(:add_on, organization:) }
  let(:fixed_charge) { create(:fixed_charge, plan:, add_on:) }

  let(:customer_1) { create(:customer, organization:) }
  let(:customer_2) { create(:customer, organization:) }
  let(:active_subscription_1) do
    create(
      :subscription,
      :active,
      :anniversary,
      plan:,
      customer: customer_1,
      started_at: 2.days.ago,
      subscription_at: 2.days.ago
    )
  end

  let(:active_subscription_2) {
    create(
      :subscription,
      :active,
      :calendar,
      plan:,
      customer: customer_2,
      started_at: 15.days.ago,
      subscription_at: 2.years.ago
    )
  }
  let(:terminated_subscription) { create(:subscription, :terminated, plan:, customer: customer_1) }

  describe "#call" do
    subject(:result) { service.call }

    before do
      active_subscription_1
      active_subscription_2
      terminated_subscription
    end

    it "returns success result" do
      expect(result).to be_success
    end

    it "creates fixed charge events for all active subscriptions" do
      expect { result }.to change(FixedChargeEvent, :count).by(2)

      event_1 = FixedChargeEvent.find_by(subscription: active_subscription_1, fixed_charge:)
      event_2 = FixedChargeEvent.find_by(subscription: active_subscription_2, fixed_charge:)

      expect(event_1).to be_present
      expect(event_1.organization).to eq(active_subscription_1.organization)
      expect(event_1.units).to eq(fixed_charge.units)
      expect(event_1.timestamp).to be_within(1.second).of(active_subscription_1.started_at.beginning_of_day + 1.month)

      expect(event_2).to be_present
      expect(event_2.organization).to eq(active_subscription_2.organization)
      expect(event_2.units).to eq(fixed_charge.units)
      expect(event_2.timestamp).to be_within(1.second).of(1.month.from_now.beginning_of_month)
    end

    it "does not create events for terminated subscriptions" do
      result

      expect(FixedChargeEvent.where(subscription: terminated_subscription, fixed_charge:)).not_to exist
    end

    context "when there are no active subscriptions" do
      let(:active_subscription_1) { nil }
      let(:active_subscription_2) { nil }

      it "does not create any events" do
        expect { result }.not_to change(FixedChargeEvent, :count)
      end

      it "returns success result" do
        expect(result).to be_success
      end
    end

    context "when a subscription is provided" do
      let(:subscription) { create(:subscription, :active, :anniversary, plan:) }
      let(:other_subscription) { create(:subscription, :active, plan:) }

      before do
        subscription
        other_subscription
      end

      it "returns success result" do
        expect(result).to be_success
      end

      it "creates fixed charge event only for the provided subscription" do
        expect { result }.to change(FixedChargeEvent, :count).by(1)

        event = FixedChargeEvent.find_by(subscription:, fixed_charge:)
        expect(event).to be_present
        expect(event.organization).to eq(subscription.organization)
        expect(event.units).to eq(fixed_charge.units)
        expect(event.timestamp).to be_within(1.second).of(subscription.started_at.beginning_of_day + 1.month)
      end

      it "does not create events for other subscriptions on the same plan" do
        result

        expect(FixedChargeEvent.where(subscription: other_subscription, fixed_charge:)).not_to exist
      end
    end
  end
end
