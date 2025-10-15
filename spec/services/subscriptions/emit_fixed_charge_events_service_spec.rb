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

  let(:fixed_charge_event_create_service) { FixedChargeEvents::CreateService }

  before do
    fixed_charge_1
    fixed_charge_2
    allow(fixed_charge_event_create_service).to receive(:call!)
  end

  describe "#call" do
    subject(:result) { service.call }

    it "calls FixedChargeEvents::CreateService for each subscription and fixed charge" do
      expect(result).to be_success

      expect(fixed_charge_event_create_service).to have_received(:call!).exactly(4).times

      expect(fixed_charge_event_create_service).to have_received(:call!).with(
        subscription: subscription_1,
        fixed_charge: fixed_charge_1,
        timestamp:
      ).once

      expect(fixed_charge_event_create_service).to have_received(:call!).with(
        subscription: subscription_1,
        fixed_charge: fixed_charge_2,
        timestamp:
      ).once

      expect(fixed_charge_event_create_service).to have_received(:call!).with(
        subscription: subscription_2,
        fixed_charge: fixed_charge_1,
        timestamp:
      ).once

      expect(fixed_charge_event_create_service).to have_received(:call!).with(
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
        expect(fixed_charge_event_create_service).not_to have_received(:call!)
      end
    end

    context "when fixed charges already have events emitted on the same date" do
      before do
        create(
          :fixed_charge_event,
          subscription: subscription_1,
          fixed_charge: fixed_charge_1,
          timestamp:
        )
      end

      it "skips fixed charges that already have events and processes others" do
        expect(result).to be_success

        expect(fixed_charge_event_create_service)
          .not_to have_received(:call!)
          .with(
            subscription: subscription_1,
            fixed_charge: fixed_charge_1,
            timestamp:
          )

        expect(fixed_charge_event_create_service)
          .to have_received(:call!)
          .with(
            subscription: subscription_1,
            fixed_charge: fixed_charge_2,
            timestamp:
          )
          .once

        expect(fixed_charge_event_create_service)
          .to have_received(:call!)
          .with(
            subscription: subscription_2,
            fixed_charge: fixed_charge_1,
            timestamp:
          )
          .once

        expect(fixed_charge_event_create_service)
          .to have_received(:call!)
          .with(
            subscription: subscription_2,
            fixed_charge: fixed_charge_2,
            timestamp:
          )
          .once
      end
    end

    context "when fixed charge events exist on different dates" do
      before do
        create(
          :fixed_charge_event,
          subscription: subscription_1,
          fixed_charge: fixed_charge_1,
          timestamp: timestamp - 1.day
        )
      end

      it "processes fixed charges that have events on different dates" do
        expect(result).to be_success

        expect(fixed_charge_event_create_service)
          .to have_received(:call!)
          .with(
            subscription: subscription_1,
            fixed_charge: fixed_charge_1,
            timestamp:
          )
          .once

        expect(fixed_charge_event_create_service)
          .to have_received(:call!).with(
            subscription: subscription_1,
            fixed_charge: fixed_charge_2,
            timestamp:
          )
          .once
      end
    end

    context "when customer has a timezone" do
      let(:customer) { create(:customer, organization:, timezone: "America/New_York") }
      let(:subscription) { create(:subscription, :active, plan:, customer:) }
      let(:subscriptions) { [subscription] }
      let(:timestamp) { Time.zone.parse("2025-09-05 12:00 UTC") }
      let(:event_time) { Time.zone.parse("2025-09-05 02:00 UTC") } # Same day in NY timezone

      before do
        create(
          :fixed_charge_event,
          subscription:,
          fixed_charge: fixed_charge_1,
          timestamp: event_time
        )
      end

      it "handles timezone when checking for existing events" do
        expect(result).to be_success

        expect(fixed_charge_event_create_service)
          .not_to have_received(:call!)
          .with(
            subscription:,
            fixed_charge: fixed_charge_1,
            timestamp:
          )

        expect(fixed_charge_event_create_service)
          .to have_received(:call!)
          .with(
            subscription:,
            fixed_charge: fixed_charge_2,
            timestamp:
          )
          .once
      end
    end

    context "when billing entity has a timezone" do
      let(:billing_entity) { create(:billing_entity, timezone: "America/New_York") }
      let(:customer) { create(:customer, billing_entity:) }
      let(:subscription) { create(:subscription, :active, plan:, customer:) }
      let(:subscriptions) { [subscription] }
      let(:timestamp) { Time.zone.parse("2025-09-05 12:00 UTC") }
      let(:event_time) { Time.zone.parse("2025-09-05 02:00 UTC") } # Same day in NY timezone

      before do
        create(
          :fixed_charge_event,
          subscription:,
          fixed_charge: fixed_charge_1,
          timestamp: event_time
        )
      end

      it "handles timezone when checking for existing events" do
        expect(result).to be_success

        expect(fixed_charge_event_create_service)
          .not_to have_received(:call!)
          .with(
            subscription:,
            fixed_charge: fixed_charge_1,
            timestamp:
          )

        expect(fixed_charge_event_create_service)
          .to have_received(:call!)
          .with(
            subscription:,
            fixed_charge: fixed_charge_2,
            timestamp:
          )
          .once
      end
    end
  end
end
