# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Context do
  describe ".from" do
    it "rejects missing records" do
      expect { described_class.from }
        .to raise_error(ArgumentError, "exactly one of subscription or contract is required")
    end

    it "rejects both records" do
      expect { described_class.from(subscription: build(:subscription), contract: build(:contract)) }
        .to raise_error(ArgumentError, "exactly one of subscription or contract is required")
    end
  end

  context "with a subscription" do
    subject(:context) { described_class.from(subscription:) }

    let(:subscription) { build_stubbed(:subscription) }

    it "exposes explicit identity and shared billing attributes" do
      expect(context.subscription).to eq(subscription)
      expect(context.contract).to be_nil
      expect(context.subscription_id).to eq(subscription.id)
      expect(context.contract_id).to be_nil
      expect(context.subscription?).to be(true)
      expect(context.contract?).to be(false)
      expect(context).not_to respond_to(:id)
      expect(context.organization_id).to eq(subscription.organization_id)
      expect(context.customer).to eq(subscription.customer)
      expect(context.external_id).to eq(subscription.external_id)
      expect(context.applicable_billing_entity_id).to eq(subscription.applicable_billing_entity_id)
      expect(context.subscription_at).to eq(subscription.subscription_at)
      expect(context.organization).to eq(subscription.organization)
      expect(context.anniversary?).to eq(subscription.anniversary?)
      expect(context.plan).to eq(subscription.plan)
      expect(context.currency).to eq(subscription.plan.amount_currency)
    end

    it "preserves subscription charge duration calculation" do
      dates_service = instance_double(Subscriptions::DatesService, charges_duration_in_days: 31)
      allow(Subscriptions::DatesService).to receive(:new_instance).and_return(dates_service)
      billing_at = Time.current

      expect(context.charges_duration_at(billing_at)).to eq(31)
      expect(Subscriptions::DatesService).to have_received(:new_instance)
        .with(subscription, billing_at, current_usage: false)
    end
  end

  context "with a contract" do
    subject(:context) { described_class.from(contract:) }

    let(:contract) { build_stubbed(:contract) }

    it "exposes contract identity and shared billing attributes" do
      expect(context.contract).to eq(contract)
      expect(context.subscription).to be_nil
      expect(context.contract_id).to eq(contract.id)
      expect(context.contract?).to be(true)
      expect(context.subscription?).to be(false)
      expect(context).not_to respond_to(:id)
      expect(context.organization_id).to eq(contract.organization_id)
      expect(context.customer).to eq(contract.customer)
      expect(context.external_id).to eq(contract.external_id)
      expect(context.applicable_billing_entity_id).to eq(contract.applicable_billing_entity_id)
      expect(context.subscription_at).to eq(contract.started_at)
      expect(context.started_at).to eq(contract.started_at)
      expect(context.organization).to eq(contract.organization)
      expect(context.plan).to eq(contract.catalog_plan)
      expect(context.currency).to eq(contract.currency)
    end

    it "prevents using contract identity in subscription queries" do
      expect { context.subscription_id }
        .to raise_error(NotImplementedError, "contract-backed billing contexts do not have a subscription id")
    end

    context "with a catalog plan" do
      let(:catalog_plan) { build_stubbed(:catalog_plan, currency: "USD") }
      let(:contract) { build_stubbed(:contract, catalog_plan:) }

      it "exposes the catalog plan and its currency" do
        expect(context).to have_attributes(plan: catalog_plan, currency: "USD")
      end
    end

    context "with a customer timezone" do
      let(:customer) { build_stubbed(:customer, timezone: "America/New_York") }
      let(:contract) { build_stubbed(:contract, customer:, organization: customer.organization) }

      it "uses the customer timezone for date differences" do
        expect(
          context.date_diff_with_timezone(
            Time.zone.parse("2026-03-01 05:00:00"),
            Time.zone.parse("2026-03-31 03:59:59")
          )
        ).to eq(30)
      end
    end

    context "when terminated" do
      let(:terminated_at) { Time.zone.parse("2026-03-15 12:00:00") }
      let(:contract) { build_stubbed(:contract, status: :terminated, terminated_at:) }

      it "delegates termination checks" do
        expect(context.terminated_at?(terminated_at + 1.second)).to be(true)
      end
    end

    it "rejects subscription-only lifecycle methods" do
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
          .to raise_error(NotImplementedError, "contract-backed billing contexts do not have #{method_name} yet")
      end
    end

    it "rejects subscription charge duration calculation" do
      expect { context.charges_duration_at(Time.current) }
        .to raise_error(NotImplementedError, "contract-backed billing contexts do not have charges_duration_at yet")
    end
  end
end
