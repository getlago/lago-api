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

    context "with a catalog plan" do
      let(:catalog_plan) { create(:catalog_plan, organization:) }
      let(:entitlement) { create(:entitlement, :catalog_plan, organization:, catalog_plan:, feature:) }
      let(:other_catalog_plan) { create(:catalog_plan, organization:) }
      let(:other_entitlement) { create(:entitlement, :catalog_plan, organization:, catalog_plan: other_catalog_plan, feature:) }
      let(:other_value) { create(:entitlement_value, entitlement: other_entitlement, privilege:, organization:, value: entitlement_value.value) }

      before do
        # The per-entitlement events of a catalog plan are behind the entitlement_events flag.
        organization.enable_feature_flag!(:entitlement_events)
        other_value
        allow(Utils::ActivityLog).to receive(:produce).and_call_original
      end

      context "without the entitlement_events flag" do
        before { organization.disable_feature_flag!(:entitlement_events) }

        it "discards the entitlement, logs nothing and sends no webhook" do
          expect { result }.not_to have_enqueued_job(SendWebhookJob)

          expect(result).to be_success
          expect(entitlement.reload).to be_discarded
          expect(Utils::ActivityLog).not_to have_received(:produce)
        end
      end

      it "discards the entitlement and its value, and keeps those of another catalog plan" do
        expect(result).to be_success
        expect(result.entitlement).to eq(entitlement)
        expect(entitlement.reload).to be_discarded
        expect(entitlement_value.reload).to be_discarded
        expect(other_entitlement.reload).not_to be_discarded
        expect(other_value.reload).not_to be_discarded
      end

      it "sends one `plan_entitlement.deleted` webhook with the values it held, and no `plan.updated` webhook" do
        expect { result }
          .to have_enqueued_job_after_commit(SendWebhookJob)
          .with("plan_entitlement.deleted", entitlement, {values: [{privilege_code: privilege.code, value: entitlement_value.value}]})
          .exactly(:once)
          .and not_have_enqueued_job(SendWebhookJob).with("plan.updated", anything)
      end

      it "produces one `plan_entitlement.deleted` activity log with the values it held, and no `plan.updated`" do
        result

        values = [{privilege_code: privilege.code, value: entitlement_value.value}]
        deleted = Entitlement::Entitlement.with_discarded.find(entitlement.id)
        expect(Utils::ActivityLog).to have_received(:produce).with(
          entitlement, "plan_entitlement.deleted", after_commit: true,
          changes: {"values" => [values, nil]},
          activity_object: {
            lago_id: entitlement.id,
            plan_code: catalog_plan.code,
            feature_code: feature.code,
            values:,
            created_at: deleted.created_at.iso8601,
            updated_at: deleted.updated_at.iso8601,
            deleted_at: deleted.deleted_at.iso8601
          }
        ).once
        expect(Utils::ActivityLog).to have_received(:produce).once
      end

      context "when the entitlement was discarded since it was loaded" do
        before { Entitlement::Entitlement.find(entitlement.id).discard! }

        it "returns a not found feature failure and sends no event" do
          expect { result }.not_to have_enqueued_job(SendWebhookJob)

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.resource).to eq("feature")
          expect(Utils::ActivityLog).not_to have_received(:produce)
        end
      end

      context "when the catalog plan is discarded" do
        before do
          catalog_plan.discard!
          entitlement.reload
        end

        it "returns a not found plan failure, discards nothing and sends no webhook or activity log" do
          expect { result }.not_to have_enqueued_job(SendWebhookJob)
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.resource).to eq("plan")
          expect(entitlement.reload).not_to be_discarded
          expect(entitlement_value.reload).not_to be_discarded
          expect(Utils::ActivityLog).not_to have_received(:produce)
        end
      end
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
      def hold_plan_lock(plan_id, model: Plan)
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ActiveRecord::Base.transaction do
              locked_plan = model.lock("FOR NO KEY UPDATE").find(plan_id)
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

      context "with a catalog plan" do
        let(:catalog_plan) { create(:catalog_plan, organization:) }
        let(:entitlement) { create(:entitlement, :catalog_plan, organization:, catalog_plan:, feature:) }

        it "answers success to the first of two concurrent deletes and not found to the second, with one event" do
          organization.enable_feature_flag!(:entitlement_events)
          allow(Utils::ActivityLog).to receive(:produce).and_call_original
          holder = hold_plan_lock(catalog_plan.id, model: CatalogPlan)
          locked.pop

          destroyers = Array.new(2) { destroy(entitlement.id) }
          expect(destroyers.map { it.join(0.5).nil? }).to eq([true, true])

          release << ->(_) {}
          holder.join
          results = destroyers.map(&:value)
          expect(results.count(&:success?)).to eq(1)
          expect(results.reject(&:success?).sole.error.resource).to eq("feature")
          expect(Entitlement::Entitlement.where(id: entitlement.id)).not_to exist
          expect(SendWebhookJob).to have_been_enqueued.with("plan_entitlement.deleted", entitlement, {values: anything}).once
          expect(Utils::ActivityLog).to have_received(:produce)
            .with(entitlement, "plan_entitlement.deleted", hash_including(after_commit: true)).once
        end

        it "waits for the catalog plan lock, then deletes the entitlement" do
          holder = hold_plan_lock(catalog_plan.id, model: CatalogPlan)
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
      end

      it "deletes once and answers not found to the second of two concurrent deletes" do
        holder = hold_plan_lock(plan.id)
        locked.pop

        destroyers = Array.new(2) { destroy(entitlement.id) }
        expect(destroyers.map { it.join(0.5).nil? }).to eq([true, true])

        release << ->(_) {}
        holder.join
        results = destroyers.map(&:value)

        expect(results.count(&:success?)).to eq(1)
        failure = results.find(&:failure?)
        expect(failure.error).to be_a(BaseService::NotFoundFailure)
        expect(failure.error.resource).to eq("entitlement")
        expect(Entitlement::Entitlement.unscoped.where(id: entitlement.id).pick(:deleted_at)).to be_present
        expect(SendWebhookJob).to have_been_enqueued.with("plan.updated", plan).once
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

      it "returns a not found failure and keeps the first deletion" do
        deleted_at = entitlement.reload.deleted_at

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("entitlement")
        expect(entitlement.reload.deleted_at).to eq(deleted_at)
        expect(SendWebhookJob).not_to have_been_enqueued
      end
    end
  end
end
