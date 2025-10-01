# frozen_string_literal: true

require "rails_helper"

RSpec.describe Plans::SyncNewChargesWithChildrenService do
  subject(:sync_service) { described_class.new(plan:) }

  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:billable_metric) { create(:billable_metric, organization:) }

  describe "#call" do
    context "when plan has no charges" do
      it "does not enqueue any jobs" do
        expect { sync_service.call }.not_to have_enqueued_job(Charges::SyncChildrenBatchJob)
      end
    end

    context "when plan has charges but no child plans" do
      let(:charge) { create(:standard_charge, plan:, billable_metric:) }

      it "does not enqueue any jobs" do
        expect { sync_service.call }.not_to have_enqueued_job(Charges::SyncChildrenBatchJob)
      end
    end

    context "when plan has charges and child plans with subscriptions" do
      let(:charge1) { create(:standard_charge, plan:, billable_metric:) }
      let(:charge2) { create(:graduated_charge, plan:, billable_metric:) }

      let(:child_plan1) { create(:plan, organization:, parent: plan) }
      let(:child_plan2) { create(:plan, organization:, parent: plan) }
      let(:child_plan3) { create(:plan, organization:, parent: plan) }

      let(:active_subscription1) { create(:subscription, plan: child_plan1, status: :active) }
      let(:pending_subscription2) { create(:subscription, plan: child_plan2, status: :pending) }
      let(:terminated_subscription3) { create(:subscription, plan: child_plan3, status: :terminated) }

      before do
        charge1
        charge2
        active_subscription1
        pending_subscription2
        terminated_subscription3
      end

      it "enqueues jobs for each charge with child plans that have active or pending subscriptions" do
        expect { sync_service.call }
          .to have_enqueued_job(Charges::SyncChildrenBatchJob)
          .with(children_plans_ids: match_array([child_plan1.id, child_plan2.id]), charge: charge1)
          .and have_enqueued_job(Charges::SyncChildrenBatchJob)
          .with(children_plans_ids: match_array([child_plan1.id, child_plan2.id]), charge: charge2)
      end

      it "does not include child plans with terminated subscriptions" do
        sync_service.call

        expect(Charges::SyncChildrenBatchJob).to have_been_enqueued
          .with(children_plans_ids: match_array([child_plan1.id, child_plan2.id]), charge: charge1)
        expect(Charges::SyncChildrenBatchJob).not_to have_been_enqueued
          .with(children_plans_ids: include(child_plan3.id), charge: charge1)
      end
    end

    context "when child plans have multiple subscriptions" do
      let(:charge) { create(:standard_charge, plan:, billable_metric:) }
      let(:child_plan) { create(:plan, organization:, parent: plan) }

      let(:active_subscription) { create(:subscription, plan: child_plan, status: :active) }
      let(:pending_subscription) { create(:subscription, plan: child_plan, status: :pending) }
      let(:terminated_subscription) { create(:subscription, plan: child_plan, status: :terminated) }

      before do
        charge
        child_plan
        active_subscription
        pending_subscription
        terminated_subscription
      end

      it "includes the child plan only once" do
        expect { sync_service.call }
          .to have_enqueued_job(Charges::SyncChildrenBatchJob)
          .with(children_plans_ids: [child_plan.id], charge:)
      end
    end

    context "when there are more than 20 child plans" do
      let(:charge) { create(:standard_charge, plan:, billable_metric:) }
      let(:child_plans) do
        (1..25).map do |i|
          child_plan = create(:plan, organization:, parent: plan)
          create(:subscription, plan: child_plan, status: :active)
          child_plan
        end
      end

      before do
        charge
        child_plans
      end

      it "batches child plans into groups of 20" do
        expect { sync_service.call }
          .to have_enqueued_job(Charges::SyncChildrenBatchJob).exactly(2).times
      end

      it "creates batches with correct sizes" do
        sync_service.call

        enqueued_jobs = Charges::SyncChildrenBatchJob.queue_adapter.enqueued_jobs
        expect(enqueued_jobs.length).to eq(2)

        # Check that we have one batch of 20 and one batch of 5
        # The exact order doesn't matter, just that we have these two sizes
        batch_sizes = enqueued_jobs.map do |job|
          args = job[:args] || job["args"]
          children_plans_ids = args[0][:children_plans_ids] || args[0]["children_plans_ids"]
          children_plans_ids.length
        end
        expect(batch_sizes).to contain_exactly(20, 5)
      end

      it "enqueues the correct number of jobs" do
        expect { sync_service.call }
          .to have_enqueued_job(Charges::SyncChildrenBatchJob).exactly(2).times
      end
    end

    context "when child plans have only terminated subscriptions" do
      let(:charge) { create(:standard_charge, plan:, billable_metric:) }
      let(:child_plan) { create(:plan, organization:, parent: plan) }
      let(:terminated_subscription) { create(:subscription, plan: child_plan, status: :terminated) }

      before do
        charge
        terminated_subscription
      end

      it "does not enqueue any jobs" do
        expect { sync_service.call }.not_to have_enqueued_job(Charges::SyncChildrenBatchJob)
      end
    end

    context "when child plans have mixed subscription statuses" do
      let(:charge) { create(:standard_charge, plan:, billable_metric:) }

      let(:child_plan_active) { create(:plan, organization:, parent: plan) }
      let(:child_plan_pending) { create(:plan, organization:, parent: plan) }
      let(:child_plan_terminated) { create(:plan, organization:, parent: plan) }
      let(:child_plan_canceled) { create(:plan, organization:, parent: plan) }

      let(:active_subscription) { create(:subscription, plan: child_plan_active, status: :active) }
      let(:pending_subscription) { create(:subscription, plan: child_plan_pending, status: :pending) }
      let(:terminated_subscription) { create(:subscription, plan: child_plan_terminated, status: :terminated) }
      let(:canceled_subscription) { create(:subscription, plan: child_plan_canceled, status: :canceled) }

      before do
        charge
        active_subscription
        pending_subscription
        terminated_subscription
        canceled_subscription
      end

      it "only includes child plans with active or pending subscriptions" do
        expected_child_ids = [child_plan_active.id, child_plan_pending.id]

        expect { sync_service.call }
          .to have_enqueued_job(Charges::SyncChildrenBatchJob)
          .with(children_plans_ids: match_array(expected_child_ids), charge:)
      end
    end

    context "when plan has charges for the same billable metric and charge model" do
      let(:charge1) { create(:standard_charge, plan:, billable_metric:) }
      let(:charge2) { create(:standard_charge, plan:, billable_metric:) }

      before do
        charge1
        charge2
      end

      it "returns forbidden failure with undistinguishable charges code" do
        result = sync_service.call

        expect(result).not_to be_success
        expect(result.error.code).to eq("plan_has_undistinguishable_charges")
      end

      it "does not enqueue any jobs" do
        expect { sync_service.call }.not_to have_enqueued_job(Charges::SyncChildrenBatchJob)
      end
    end
  end
end
