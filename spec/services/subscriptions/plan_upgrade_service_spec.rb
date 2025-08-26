# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::PlanUpgradeService, type: :service do
  subject(:result) do
    described_class.call(current_subscription: subscription, plan:, params:)
  end

  let(:subscription) do
    create(
      :subscription,
      customer:,
      plan: old_plan,
      status: :active,
      subscription_at: Time.current,
      started_at: Time.current,
      external_id: SecureRandom.uuid
    )
  end

  let(:old_plan) { create(:plan, amount_cents: 100, organization:, amount_currency: currency) }
  let(:customer) { create(:customer, :with_hubspot_integration, organization:, currency:) }
  let(:organization) { create(:organization) }
  let(:currency) { "EUR" }
  let(:plan) { create(:plan, amount_cents: 100, organization:) }
  let(:params) { {name: subscription_name} }
  let(:subscription_name) { "new invoice display name" }

  describe "#call", :aggregate_failures do
    before do
      subscription.mark_as_active!
    end

    it "terminates the existing subscription" do
      expect { result }
        .to change { subscription.reload.status }.from("active").to("terminated")
    end

    it "moves the lifetime_usage to the new subscription" do
      lifetime_usage = subscription.lifetime_usage
      expect(result.subscription.lifetime_usage).to eq(lifetime_usage.reload)
      expect(subscription.reload.lifetime_usage).to be_nil
    end

    it "sends terminated and started subscription webhooks" do
      result
      expect(SendWebhookJob).to have_been_enqueued.with("subscription.terminated", subscription)
      expect(SendWebhookJob).to have_been_enqueued.with("subscription.started", result.subscription)
    end

    it "produces an activity log" do
      result
      expect(Utils::ActivityLog).to have_produced("subscription.started").with(result.subscription)
    end

    it "enqueues the Hubspot update job" do
      # TODO: review this one, this one should fail because the code conditional
      # is not meet by the test setup...
      # The subscription does not start in the future
      result
      expect(Integrations::Aggregator::Subscriptions::Hubspot::UpdateJob).to have_been_enqueued.twice.with(subscription:)
    end

    it "creates a new subscription" do
      expect(result).to be_success
      expect(result.subscription.id).not_to eq(subscription.id)
      expect(result.subscription).to be_active
      expect(result.subscription.name).to eq(subscription_name)
      expect(result.subscription.plan.id).to eq(plan.id)
      expect(result.subscription.previous_subscription_id).to eq(subscription.id)
      expect(result.subscription.subscription_at).to eq(subscription.subscription_at)
    end

    context "when current subscription is pending" do
      before { subscription.pending! }

      it "returns existing subscription with updated attributes" do
        expect(result).to be_success
        expect(result.subscription.id).to eq(subscription.id)
        expect(result.subscription.plan_id).to eq(plan.id)
        expect(result.subscription.name).to eq(subscription_name)
      end
    end

    context "when old subscription is payed in arrear" do
      let(:old_plan) { create(:plan, amount_cents: 100, organization:, pay_in_advance: false) }

      it "enqueues a job to bill the existing subscription" do
        expect { result }.to have_enqueued_job(BillSubscriptionJob)
      end
    end

    context "when old subscription was payed in advance" do
      let(:creation_time) { Time.current.beginning_of_month - 1.month }
      let(:date_service) do
        Subscriptions::DatesService.new_instance(
          subscription,
          Time.current.beginning_of_month,
          current_usage: false
        )
      end

      let(:invoice_subscription) do
        create(
          :invoice_subscription,
          invoice:,
          subscription:,
          recurring: true,
          from_datetime: date_service.from_datetime,
          to_datetime: date_service.to_datetime,
          charges_from_datetime: date_service.charges_from_datetime,
          charges_to_datetime: date_service.charges_to_datetime
        )
      end

      let(:invoice) do
        create(
          :invoice,
          customer:,
          currency:,
          sub_total_excluding_taxes_amount_cents: 100,
          fees_amount_cents: 100,
          taxes_amount_cents: 20,
          total_amount_cents: 120
        )
      end

      let(:last_subscription_fee) do
        create(
          :fee,
          subscription:,
          invoice:,
          amount_cents: 100,
          taxes_amount_cents: 20,
          invoiceable_type: "Subscription",
          invoiceable_id: subscription.id,
          taxes_rate: 20
        )
      end

      let(:subscription) do
        create(
          :subscription,
          customer:,
          plan: old_plan,
          status: :active,
          subscription_at: creation_time,
          started_at: creation_time,
          external_id: SecureRandom.uuid,
          billing_time: "anniversary"
        )
      end

      let(:old_plan) { create(:plan, amount_cents: 100, organization:, pay_in_advance: true) }

      before do
        invoice_subscription
        last_subscription_fee
      end

      it "creates a credit note for the remaining days" do
        expect { result }.to change(CreditNote, :count)
      end
    end

    context "when new subscription is payed in advance" do
      let(:plan) { create(:plan, amount_cents: 200, organization:, pay_in_advance: true) }

      it "enqueues a job to bill the existing subscription" do
        expect { result }.to have_enqueued_job(BillSubscriptionJob)
      end
    end

    context "with pending next subscription" do
      let(:next_subscription) do
        create(
          :subscription,
          status: :pending,
          previous_subscription: subscription,
          organization:,
          customer:
        )
      end

      before { next_subscription }

      it "canceled the next subscription" do
        expect(result).to be_success
        expect(next_subscription.reload).to be_canceled
      end
    end

    context "when sending plan_overrides" do
      context "when License is premium" do
        around { |test| lago_premium!(&test) }

        context "when upgrading with plan_overrides that contain only fixed_charges with units" do
          let(:add_on) { create(:add_on, organization:) }
          let(:fixed_charge) { create(:fixed_charge, plan:, add_on:, organization:, units: 2) }
          let(:fixed_charge2) { create(:fixed_charge, plan:, add_on:, organization:, units: 3) }
          let(:params) do
            {
              name: subscription_name,
              plan_overrides: {
                fixed_charges: [
                  {id: fixed_charge.id, units: 5},
                  {id: fixed_charge2.id, units: 7}
                ]
              }
            }
          end

          before do
            fixed_charge
            fixed_charge2
          end

          it "creates new subscription with original plan and fixed charge unit overrides" do
            expect(result).to be_success
            expect(result.subscription.plan).to eq(plan)
            expect(result.subscription.subscription_fixed_charge_units_overrides.count).to eq(2)
            expect(result.subscription.subscription_fixed_charge_units_overrides.map(&:units)).to match_array([5, 7])
          end

          it "only calls FixedChargeUnitOverrideService for each fixed charge" do
            allow(Subscriptions::FixedChargeUnitOverrideService).to receive(:call!)
            allow(Plans::OverrideService).to receive(:call)

            result

            expect(Subscriptions::FixedChargeUnitOverrideService).to have_received(:call!).twice
            expect(Plans::OverrideService).not_to have_received(:call)
          end
        end

        context "when plan_overrides contains other fields changes, but only units are changed for fixed_charges" do
          let(:add_on) { create(:add_on, organization:) }
          let(:fixed_charge) { create(:fixed_charge, plan:, add_on:, organization:, units: 2) }
          let(:params) do
            {
              name: subscription_name,
              plan_overrides: {
                fixed_charges: [
                  {id: fixed_charge.id, units: 5}
                ],
                amount_cents: 200
              }
            }
          end

          before do
            fixed_charge
          end

          it "calls Plans::OverrideService instead of creating unit overrides" do
            allow(Plans::OverrideService).to receive(:call).and_call_original
            allow(Subscriptions::FixedChargeUnitOverrideService).to receive(:call!)

            result

            expect(Plans::OverrideService).to have_received(:call)
            expect(Subscriptions::FixedChargeUnitOverrideService).not_to have_received(:call!)
          end
        end
      end
    end
  end
end
