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
      expect(context.purchase_order_number).to eq(subscription.purchase_order_number)
      expect(context.applicable_billing_entity_id).to eq(subscription.applicable_billing_entity_id)
      expect(context.purchase_order_number).to eq(subscription.purchase_order_number)
      expect(context.subscription_at).to eq(subscription.subscription_at)
      expect(context.organization).to eq(subscription.organization)
      expect(context.currency).to eq(subscription.plan.amount_currency)
      expect(context.fees.proxy_association.owner).to eq(subscription)
      expect(context.anniversary?).to eq(subscription.anniversary?)
      expect(context.active?).to eq(subscription.active?)
      expect(context).not_to respond_to(:plan)
      expect(context).not_to respond_to(:next_subscription)
    end

    it "preserves subscription relationships" do
      expect(context.invoice_subscriptions.proxy_association.owner).to eq(subscription)
      expect(context.previous_subscription).to be_nil
      expect(context.previous_subscription_id).to be_nil
      expect(context.previous_subscription_id?).to be(false)
      expect(context.upgraded?).to be(false)
      expect(context.downgraded?).to be(false)
    end

    context "with a predecessor subscription" do
      let(:predecessor) { build_stubbed(:subscription) }
      let(:subscription) { build_stubbed(:subscription, previous_subscription: predecessor) }

      it "preserves predecessor identity" do
        expect(context.previous_subscription).to eq(predecessor)
        expect(context.previous_subscription_id).to eq(predecessor.id)
        expect(context.previous_subscription_id?).to be(true)
      end
    end

    context "with a successor subscription" do
      let(:plan) { build_stubbed(:plan, amount_cents: 1000) }
      let(:subscription) { build_stubbed(:subscription, plan:) }
      let(:successor_plan) { build_stubbed(:plan, amount_cents: 2000) }
      let(:successor) { build_stubbed(:subscription, plan: successor_plan) }

      before do
        allow(subscription).to receive(:next_subscription).and_return(successor)
      end

      it "preserves upgrade classification" do
        expect(context.upgraded?).to be(true)
        expect(context.downgraded?).to be(false)
      end

      context "with a cheaper successor plan" do
        let(:successor_plan) { build_stubbed(:plan, amount_cents: 500) }

        it "preserves downgrade classification" do
          expect(context.upgraded?).to be(false)
          expect(context.downgraded?).to be(true)
        end
      end
    end

    context "when the subscription has a billing entity" do
      let(:billing_entity) { build_stubbed(:billing_entity) }
      let(:subscription) { build_stubbed(:subscription, billing_entity:) }

      it "uses the subscription billing entity" do
        expect(context.applicable_billing_entity).to eq(billing_entity)
      end
    end

    context "when the subscription has no billing entity" do
      let(:billing_entity) { build_stubbed(:billing_entity) }
      let(:customer) { build_stubbed(:customer, billing_entity:) }
      let(:subscription) { build_stubbed(:subscription, customer:, organization: customer.organization) }

      it "uses the customer billing entity" do
        expect(context.applicable_billing_entity).to eq(billing_entity)
      end
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
      expect(context.applicable_billing_entity).to eq(contract.applicable_billing_entity)
      expect(context.applicable_billing_entity_id).to eq(contract.applicable_billing_entity_id)
      expect(context.purchase_order_number).to eq(contract.purchase_order_number)
      expect(context.subscription_at).to eq(contract.started_at)
      expect(context.started_at).to eq(contract.started_at)
      expect(context.organization).to eq(contract.organization)
      expect(context.currency).to eq(contract.currency)
      expect(context.fees.proxy_association.owner).to eq(contract)
      expect(context.active?).to eq(contract.active?)
    end

    it "prevents using contract identity in subscription queries" do
      expect(context.subscription_id).to be_nil
      expect(context.plan_id).to be_nil
      expect(context).not_to respond_to(:next_subscription)
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

    it "returns neutral subscription relationships and lifecycle predicates" do
      expect(context.invoice_subscriptions).to eq([])
      expect(context.previous_subscription).to be_nil
      expect(context.previous_subscription_id).to be_nil
      expect(context.previous_subscription_id?).to be(false)
      expect(context.upgraded?).to be(false)
      expect(context.downgraded?).to be(false)
    end
  end
end
