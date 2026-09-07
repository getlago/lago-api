# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::Stores::EventContext do
  describe ".from" do
    it "wraps a subscription" do
      subscription = create(:subscription)

      context = described_class.from(subscription:)

      expect(context.external_id).to eq(subscription.external_id)
      expect(context.id).to eq(subscription.id)
      expect(context.organization).to eq(subscription.organization)
      expect(context.customer).to eq(subscription.customer)
      expect(context.subscription_at).to eq(subscription.subscription_at)
      expect(context.anniversary?).to eq(subscription.anniversary?)
    end

    it "wraps a contract for raw event lookup" do
      contract = create(:contract)

      context = described_class.from(contract:)

      expect(context.external_id).to eq(contract.external_id)
      expect(context.organization).to eq(contract.organization)
      expect(context.customer).to eq(contract.customer)
      expect(context.started_at).to eq(contract.started_at)
    end

    it "rejects missing records" do
      expect { described_class.from }.to raise_error(ArgumentError, "subscription or contract is required")
    end

    it "rejects ambiguous records" do
      expect { described_class.from(subscription: build(:subscription), contract: build(:contract)) }
        .to raise_error(ArgumentError, "subscription or contract is required")
    end
  end

  describe "#id" do
    it "rejects subscription ids for contract-backed contexts" do
      context = described_class.from(contract: create(:contract))

      expect { context.id }
        .to raise_error(NotImplementedError, "contract-backed event contexts do not have a subscription id")
    end
  end

  describe "#date_diff_with_timezone" do
    it "uses the customer timezone for contracts" do
      customer = create(:customer, timezone: "America/New_York")
      contract = create(:contract, customer:, organization: customer.organization)
      context = described_class.from(contract:)

      expect(
        context.date_diff_with_timezone(
          Time.zone.parse("2026-03-01 05:00:00"),
          Time.zone.parse("2026-03-31 03:59:59")
        )
      ).to eq(30)
    end
  end

  describe "#terminated_at?" do
    it "delegates to a contract-backed context" do
      contract = create(:contract, status: :terminated, terminated_at: Time.zone.parse("2026-03-15 12:00:00"))
      context = described_class.from(contract:)

      expect(context.terminated_at?(Time.zone.parse("2026-03-15 12:00:01"))).to eq(true)
    end
  end

  describe "subscription-only methods" do
    it "raises for contract-backed contexts" do
      context = described_class.from(contract: create(:contract))

      %i[
        invoice_subscriptions
        previous_subscription
        previous_subscription_id
        previous_subscription_id?
        next_subscription
        upgraded?
        downgraded?
      ].each do |method_name|
        expect { context.public_send(method_name) }
          .to raise_error(NotImplementedError, "contract-backed event contexts do not have #{method_name} yet")
      end
    end
  end

  describe "#charges_duration_at" do
    it "delegates period duration computation through Subscriptions::DatesService" do
      subscription = create(:subscription, started_at: Time.zone.parse("2026-03-01"))
      context = described_class.from(subscription:)

      dates_service = instance_double(Subscriptions::DatesService, charges_duration_in_days: 31)
      allow(Subscriptions::DatesService).to receive(:new_instance).and_return(dates_service)

      expect(context.charges_duration_at(Time.zone.parse("2026-04-01"))).to eq(31)
      expect(Subscriptions::DatesService).to have_received(:new_instance)
        .with(subscription, Time.zone.parse("2026-04-01"), current_usage: false)
    end

    it "rejects charge duration computation for contracts" do
      context = described_class.from(contract: create(:contract))

      expect { context.charges_duration_at(Time.current) }
        .to raise_error(NotImplementedError, "contract-backed event contexts do not have charge durations yet")
    end
  end
end
