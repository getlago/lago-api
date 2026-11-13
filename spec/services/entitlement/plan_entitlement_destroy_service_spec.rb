# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::PlanEntitlementDestroyService do
  subject(:result) { described_class.call(entitlement:) }

  # Plain lets: the thread examples run without a transaction, where shared records would stay uncommitted.
  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:feature) { create(:feature, organization:) }
  let(:privilege) { create(:privilege, organization:, feature:) }
  let(:entitlement) { create(:entitlement, organization:, plan:, feature:) }
  let(:entitlement_value) { create(:entitlement_value, entitlement:, privilege:, organization:) }

  before do
    entitlement_value
  end

  describe "#call", :premium do
    it "returns success" do
      expect(result).to be_success
    end

    it "soft deletes the entitlement" do
      expect { result }.to change(feature.entitlements, :count).by(-1)
    end

    it "soft deletes all entitlement values" do
      expect { result }.to change(feature.entitlement_values, :count).by(-1)
    end

    it "returns the entitlement in the result" do
      expect(result.entitlement).to eq(entitlement)
    end

    it "sends `plan.updated` webhook" do
      expect { subject }.to have_enqueued_job_after_commit(SendWebhookJob).with("plan.updated", plan)
    end

    it "produces an activity log" do
      subject
      expect(Utils::ActivityLog).to have_produced("plan.updated").after_commit.with(plan)
    end

    context "when entitlement is nil" do
      subject(:result) { described_class.call(entitlement: nil) }

      it "returns not found failure" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("entitlement_not_found")
      end
    end

    context "when the plan is discarded" do
      before do
        plan.discard!
        entitlement.reload
      end

      it "returns a not found plan failure and discards nothing" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("plan")
        expect(entitlement.reload).not_to be_discarded
        expect(entitlement_value.reload).not_to be_discarded
      end

      it "sends no webhook and produces no activity log" do
        expect { result }.not_to have_enqueued_job(SendWebhookJob)
        expect(Utils::ActivityLog).not_to have_produced("plan.updated")
      end
    end

    context "with threads", transaction: false do
      let(:locked) { Queue.new }
      let(:release) { Queue.new }

      # Frees a lock holder left waiting by a failed expectation.
      after { release << ->(_) {} }

      def destroy(entitlement_id)
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            described_class.call(entitlement: Entitlement::Entitlement.find(entitlement_id))
          end
        end
      end

      # Holds the plan row lock in another connection until `release` receives the block to run before the commit.
      def hold_plan_lock(plan_id)
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ActiveRecord::Base.transaction do
              locked_plan = Plan.lock("FOR NO KEY UPDATE").find(plan_id)
              locked << true
              release.pop.call(locked_plan)
            end
          end
        end
      end

      it "waits for the plan lock, then deletes the entitlement" do
        holder = hold_plan_lock(plan.id)
        locked.pop

        destroyer = destroy(entitlement.id)
        expect(destroyer.join(0.5)).to be_nil
        expect(Entitlement::Entitlement.where(id: entitlement.id)).to exist

        release << ->(_) {}
        holder.join
        expect(destroyer.value).to be_success
        expect(Entitlement::Entitlement.where(id: entitlement.id)).not_to exist
        expect(Entitlement::EntitlementValue.where(id: entitlement_value.id)).not_to exist
      end

      it "answers success to two concurrent deletes of one entitlement" do
        holder = hold_plan_lock(plan.id)
        locked.pop

        destroyers = Array.new(2) { destroy(entitlement.id) }
        expect(destroyers.map { it.join(0.5).nil? }).to eq([true, true])

        release << ->(_) {}
        holder.join
        expect(destroyers.map(&:value)).to all(be_success)
        expect(Entitlement::Entitlement.where(id: entitlement.id)).not_to exist
      end

      it "refuses a delete on a plan discarded while it waits for the lock" do
        holder = hold_plan_lock(plan.id)
        locked.pop

        destroyer = destroy(entitlement.id)
        expect(destroyer.join(0.5)).to be_nil

        release << ->(locked_plan) { locked_plan.update_columns(deleted_at: Time.current) } # rubocop:disable Rails/SkipsModelValidations
        holder.join
        result = destroyer.value

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("plan")
        expect(Entitlement::Entitlement.where(id: entitlement.id)).to exist
        expect(Entitlement::EntitlementValue.where(id: entitlement_value.id)).to exist
      end
    end

    context "when entitlement is already deleted" do
      before do
        entitlement.discard!
      end

      it "still soft deletes the entitlement values" do
        expect { result }.to raise_error(Discard::RecordNotDiscarded)
      end
    end
  end
end
