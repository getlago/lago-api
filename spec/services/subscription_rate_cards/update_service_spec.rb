# frozen_string_literal: true

require "rails_helper"

RSpec.describe SubscriptionRateCards::UpdateService do
  subject(:result) { described_class.call(subscription_rate_card:, params:) }

  let(:organization) { create(:organization) }
  let(:subscription) { create(:subscription, :pending, organization:) }
  let(:subscription_rate_card) { create(:subscription_rate_card, organization:, subscription:, units: 5) }

  let(:params) { {units: "12"} }

  it "updates the entry" do
    expect(result).to be_success
    expect(result.subscription_rate_card.units).to eq(12)
  end

  context "when moving the start date" do
    let(:params) { {started_at: Time.zone.parse("2026-09-01")} }

    it "moves the billing clock along with it" do
      item = result.subscription_rate_card
      expect(item.started_at).to eq(Time.zone.parse("2026-09-01"))
      expect(item.next_billing_at).to eq(Time.zone.parse("2026-09-01"))
    end
  end

  context "when updating the billing anchor" do
    let(:params) { {billing_anchor_date: "2026-09-15"} }

    it "updates it" do
      expect(result.subscription_rate_card.billing_anchor_date).to eq(Date.parse("2026-09-15"))
    end
  end

  context "when updating the billing anchor with a malformed value" do
    let(:params) { {billing_anchor_date: "hello"} }

    it "returns a validation failure instead of crashing on the date cast" do
      expect(result).not_to be_success
      expect(result.error.messages[:billing_anchor_date]).to eq(["value_is_invalid"])
    end
  end

  context "when the subscription is active" do
    let(:subscription) { create(:subscription, organization:) }
    let(:subscription_rate_card) do
      create(:subscription_rate_card, organization:, subscription:, units: 5, next_billing_at: 10.days.from_now)
    end

    context "when changing a locked field" do
      let(:params) { {started_at: Time.zone.parse("2026-09-01")} }

      it "forbids the update" do
        expect(result).not_to be_success
        expect(result.error.messages[:started_at]).to eq(["subscription_locked"])
      end
    end

    context "when resending unchanged values" do
      let(:params) { {units: "5", billing_anchor_date: subscription_rate_card.billing_anchor_date.to_s} }

      it "is a no-op success" do
        subscription_rate_card
        expect { result }.not_to change(SubscriptionRateCard, :count)
        expect(result).to be_success
        expect(result.subscription_rate_card).to eq(subscription_rate_card)
      end
    end

    context "when changing units without apply_units" do
      let(:params) { {units: "8"} }

      it "requires apply_units" do
        expect(result).not_to be_success
        expect(result.error.messages[:apply_units]).to eq(["value_is_mandatory"])
      end
    end

    context "when apply_units is unknown" do
      let(:params) { {units: "8", apply_units: "someday"} }

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:apply_units]).to eq(["value_is_invalid"])
      end
    end

    context "when applying units now" do
      let(:params) { {units: "8", apply_units: "now"} }

      before do
        create(:rate_phase, :subscription_level, organization:, subscription_rate_card:, position: 1,
          billing_interval_cycle_count: nil, code: "default")
      end

      it "closes the current version and opens a successor carrying the phases" do
        successor = result.subscription_rate_card

        expect(result).to be_success
        expect(successor.id).not_to eq(subscription_rate_card.id)
        expect(successor.units).to eq(8)
        expect(successor.ended_at).to be_nil
        expect(successor.started_at).to be_within(5.seconds).of(Time.current)
        expect(successor.rate_phases.sole.code).to eq("default")

        expect(subscription_rate_card.reload.ended_at).to be_within(5.seconds).of(Time.current)
        expect(subscription_rate_card.units).to eq(5)
      end
    end

    context "when applying units at the next billing period" do
      let(:params) { {units: "8", apply_units: "next_billing_period"} }

      it "schedules the successor at the entry's next billing time" do
        successor = result.subscription_rate_card

        expect(result).to be_success
        expect(successor.reload.started_at).to eq(subscription_rate_card.reload.next_billing_at)
        expect(subscription_rate_card.ended_at).to eq(subscription_rate_card.next_billing_at)
      end

      it "supersedes a previously scheduled change" do
        described_class.call(subscription_rate_card:, params: {units: "7", apply_units: "next_billing_period"})
        first_scheduled = subscription.applied_rate_cards.where("started_at > ?", Time.current).sole

        current = subscription.applied_rate_cards.active_at(Time.current).sole
        second = described_class.call(subscription_rate_card: current, params: {units: "9", apply_units: "next_billing_period"})

        expect(second).to be_success
        expect(first_scheduled.reload).to be_discarded
        expect(subscription.applied_rate_cards.where("started_at > ?", Time.current).sole.units).to eq(9)
      end

      it "discards the superseded version's phases and overrides" do
        override = create(:rate_override, organization:)
        phase = create(:rate_phase, :subscription_level, organization:, subscription_rate_card:, position: 1,
          billing_interval_cycle_count: nil, code: "default")
        phase.update!(rate_override_id: override.id)

        described_class.call(subscription_rate_card:, params: {units: "7", apply_units: "next_billing_period"})
        scheduled = subscription.applied_rate_cards.where("started_at > ?", Time.current).sole
        scheduled_phase = scheduled.rate_phases.sole
        scheduled_override = scheduled_phase.rate_override

        current = subscription.applied_rate_cards.active_at(Time.current).sole
        described_class.call(subscription_rate_card: current, params: {units: "9", apply_units: "next_billing_period"})

        expect(scheduled_phase.reload).to be_discarded
        expect(scheduled_override.reload).to be_discarded
      end
    end
  end

  context "when the entry is missing" do
    let(:subscription_rate_card) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("applied_rate_card")
    end
  end

  describe "units input validation" do
    context "when units are malformed" do
      let(:params) { {units: "abc"} }

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:units]).to eq(["value_is_invalid"])
      end
    end

    context "when units are negative on a pending subscription" do
      let(:subscription) { create(:subscription, :pending, organization:) }
      let(:params) { {units: "-2"} }

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:units]).to be_present
      end
    end

    context "when units are explicitly null on a pending subscription" do
      let(:subscription) { create(:subscription, :pending, organization:) }
      let(:params) { {units: nil} }

      it "clears the units" do
        expect(result).to be_success
        expect(result.subscription_rate_card.reload.units).to be_nil
      end
    end

    context "when units are negative on an active subscription" do
      let(:subscription) { create(:subscription, organization:) }
      let(:params) { {units: "-2", apply_units: "now"} }

      it "returns a validation failure without versioning" do
        subscription_rate_card

        expect { result }.not_to change(SubscriptionRateCard.with_discarded, :count)
        expect(result).not_to be_success
      end
    end
  end
end
