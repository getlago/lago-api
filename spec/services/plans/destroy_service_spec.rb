# frozen_string_literal: true

require "rails_helper"

RSpec.describe Plans::DestroyService do
  subject(:destroy_service) { described_class.new(plan:) }

  let(:organization) { create_default(:organization) }
  let(:plan) { create(:plan, organization:, pending_deletion: true) }
  let(:membership) { create(:membership) }

  before do
    plan
  end

  describe "catalog plan attachments" do
    it "discards the applied rate cards, their phases and overrides" do
      organization = create(:organization, feature_flags: ["product_catalog"])
      plan = create(:plan, :product_catalog, organization:, pending_deletion: true)
      product = create(:product, organization:)
      rate_card = create(:rate_card, organization:, product:, currency: plan.amount_currency)
      entry = plan.applied_rate_cards.create!(organization:, rate_card:, units: 1)
      override = create(:rate_override, organization:)
      phase = create(:rate_phase, organization:, plan_rate_card: entry, position: 1, rate_override: override)

      result = described_class.call(plan:)

      expect(result).to be_success
      expect(entry.reload).to be_discarded
      expect(phase.reload).to be_discarded
      expect(override.reload).to be_discarded
      expect(rate_card.reload).not_to be_attached_to_plan_or_subscription
    end
  end

  describe "#call" do
    it "soft deletes the plan" do
      freeze_time do
        expect { destroy_service.call }.to change(Plan, :count).by(-1)
          .and change { plan.reload.deleted_at }.from(nil).to(Time.current)
      end
    end

    it "sets pending_deletion to false" do
      expect { destroy_service.call }.to change { plan.reload.pending_deletion }.from(true).to(false)
    end

    it "produces an activity log" do
      described_class.call(plan:)

      expect(Utils::ActivityLog).to have_produced("plan.deleted").after_commit.with(plan)
    end

    context "when plan is not found" do
      let(:plan) { nil }

      it "returns an error" do
        result = destroy_service.call

        expect(result).not_to be_success
        expect(result.error.error_code).to eq("plan_not_found")
      end
    end

    context "with active subscriptions" do
      let(:subscriptions) { create_list(:subscription, 2, plan:) }

      before { subscriptions }

      it "terminates the subscriptions" do
        result = destroy_service.call

        expect(result).to be_success

        subscriptions.each do |subscription|
          expect(subscription.reload).to be_terminated
        end
      end
    end

    context "with pending subscriptions" do
      let(:subscriptions) { create_list(:subscription, 2, :pending, plan:) }

      before { subscriptions }

      it "cancels the subscriptions" do
        result = destroy_service.call

        expect(result).to be_success

        subscriptions.each do |subscription|
          expect(subscription.reload).to be_canceled
        end
      end
    end

    context "with draft invoices" do
      let(:subscription) { create(:subscription, plan:) }
      let(:invoices) { create_list(:invoice, 2, :draft) }

      before do
        create(:invoice_subscription, invoice: invoices.first, subscription:, invoicing_reason: :subscription_starting)
        create(:invoice_subscription, invoice: invoices.second, subscription:, invoicing_reason: :subscription_periodic)
      end

      it "finalizes draft invoices" do
        result = destroy_service.call

        expect(result).to be_success

        invoices.each do |invoice|
          expect(invoice.reload).to be_finalized
        end
      end
    end

    context "with entitlements" do
      let(:entitlement) { create(:entitlement, plan:) }
      let(:entitlement_value) { create(:entitlement_value, entitlement: entitlement, privilege: create(:privilege, feature: entitlement.feature)) }

      before do
        entitlement
        entitlement_value
      end

      it "destroys the entitlements" do
        destroy_service.call
        expect(entitlement.reload).to be_discarded
        expect(entitlement_value.reload).to be_discarded
      end
    end

    context "when plan is already discarded" do
      let(:plan) { create(:plan, :deleted, organization:) }

      it "returns the deleted plan" do
        result = destroy_service.call

        expect(result).to be_success
        expect(result.plan).to eq(plan)
      end
    end
  end
end
