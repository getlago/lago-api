# frozen_string_literal: true

require "rails_helper"

RSpec.describe Plans::DestroyService, type: :service do
  subject(:destroy_service) { described_class.new(plan:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:plan) { create(:plan, organization:, pending_deletion: true) }

  before { plan }

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

    context "when plan is not found" do
      let(:plan) { nil }

      it "returns an error" do
        result = destroy_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.error_code).to eq("plan_not_found")
        end
      end
    end

    it "calls SegmentTrackJob" do
      allow(SegmentTrackJob).to receive(:perform_later)

      destroy_service.call

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: "plan_deleted",
        properties: {
          code: plan.code,
          name: plan.name,
          description: plan.description,
          plan_interval: plan.interval,
          plan_amount_cents: plan.amount_cents,
          plan_period: "arrears",
          trial: plan.trial_period,
          nb_charges: plan.charges.count,
          nb_standard_charges: 0,
          nb_percentage_charges: 0,
          nb_graduated_charges: 0,
          nb_package_charges: 0,
          organization_id: plan.organization_id
        }
      )
    end

    context "with active subscriptions" do
      let(:subscriptions) { create_list(:subscription, 2, plan:) }

      before { subscriptions }

      it "terminates the subscriptions" do
        result = destroy_service.call

        aggregate_failures do
          expect(result).to be_success

          subscriptions.each do |subscription|
            expect(subscription.reload).to be_terminated
          end
        end
      end
    end

    context "with pending subscriptions" do
      let(:subscriptions) { create_list(:pending_subscription, 2, plan:) }

      before { subscriptions }

      it "cancels the subscriptions" do
        result = destroy_service.call

        aggregate_failures do
          expect(result).to be_success

          subscriptions.each do |subscription|
            expect(subscription.reload).to be_canceled
          end
        end
      end
    end

    context "with draft invoices" do
      let(:subscription) { create(:subscription, plan:) }
      let(:invoices) { create_list(:invoice, 2, :draft) }

      before do
        invoices.each do |invoice|
          create(:invoice_subscription, invoice:, subscription:)
        end
      end

      it "finalizes draft invoices" do
        result = destroy_service.call

        aggregate_failures do
          expect(result).to be_success

          invoices.each do |invoice|
            expect(invoice.reload).to be_finalized
          end
        end
      end
    end
  end
end
