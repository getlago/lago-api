# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::PlanEntitlementPrivilegeDestroyService do
  subject(:result) { described_class.call(entitlement:, privilege_code:) }

  # Plain lets: the thread examples run without a transaction, where shared records would stay uncommitted.
  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:feature) { create(:feature, organization:) }
  let(:privilege) { create(:privilege, organization:, feature:, code: "max") }
  let(:privilege2) { create(:privilege, organization:, feature:, code: "max_admins") }
  let(:entitlement) { create(:entitlement, organization:, plan:, feature:) }
  let(:entitlement_value) { create(:entitlement_value, entitlement:, privilege:, organization:) }
  let(:entitlement_value2) { create(:entitlement_value, entitlement:, privilege: privilege2, organization:) }
  let(:privilege_code) { "max" }

  before do
    entitlement_value
    entitlement_value2
  end

  describe "#call", :premium do
    it "returns success" do
      expect(result).to be_success
    end

    it "soft deletes the specific entitlement value" do
      expect { result }.to change(feature.entitlement_values, :count).by(-1)
    end

    it "does not delete other entitlement values" do
      result
      expect(entitlement.values.kept.count).to eq(1)
      expect(entitlement.values.kept.first.privilege).to eq(privilege2)
    end

    it "returns the entitlement in the result" do
      expect(result.entitlement).to eq(entitlement)
      expect(result.entitlement.values).to be_loaded
      result.entitlement.values.all? do |value|
        expect(value.association(:privilege)).to be_loaded
      end
      expect(result.entitlement.values.ids).to contain_exactly(entitlement_value2.id)
    end

    it "sends `plan.updated` webhook" do
      expect { subject }.to have_enqueued_job_after_commit(SendWebhookJob).with("plan.updated", plan)
    end

    it "produces an activity log" do
      subject
      expect(Utils::ActivityLog).to have_produced("plan.updated").after_commit.with(plan)
    end

    context "with a catalog plan entitlement" do
      let(:catalog_plan) { create(:catalog_plan, organization:) }
      let(:entitlement) { create(:entitlement, :catalog_plan, organization:, catalog_plan:, feature:) }
      let(:other_catalog_plan) { create(:catalog_plan, organization:) }
      let(:other_entitlement) { create(:entitlement, :catalog_plan, organization:, catalog_plan: other_catalog_plan, feature:) }
      let(:other_value) { create(:entitlement_value, entitlement: other_entitlement, privilege:, organization:) }

      before do
        # The per-entitlement events of a catalog plan are behind the entitlement_events flag.
        organization.enable_feature_flag!(:entitlement_events)
        other_value
        allow(Utils::ActivityLog).to receive(:produce).and_call_original
      end

      context "without the entitlement_events flag" do
        before { organization.disable_feature_flag!(:entitlement_events) }

        it "discards the value, logs nothing and sends no webhook" do
          expect { result }.not_to have_enqueued_job(SendWebhookJob)

          expect(result).to be_success
          expect(entitlement_value.reload).to be_discarded
          expect(Utils::ActivityLog).not_to have_received(:produce)
        end
      end

      it "discards the value, keeps the entitlement and the value of another catalog plan" do
        expect(result).to be_success
        expect(entitlement_value.reload).to be_discarded
        expect(entitlement.reload).not_to be_discarded
        expect(entitlement_value2.reload).not_to be_discarded
        expect(other_value.reload).not_to be_discarded
      end

      it "returns the reloaded entitlement without the value" do
        expect(result.entitlement).to eq(entitlement)
        expect(result.entitlement).not_to equal(entitlement)
        expect(result.entitlement.values).to be_loaded
        expect(result.entitlement.association(:feature)).to be_loaded
        expect(result.entitlement.values.map { it.association(:privilege).loaded? }).to eq([true])
        expect(result.entitlement.values.map(&:id)).to eq([entitlement_value2.id])
      end

      it "sends one `plan_entitlement.updated` webhook and no `plan.updated` webhook" do
        expect { result }
          .to have_enqueued_job_after_commit(SendWebhookJob).with("plan_entitlement.updated", entitlement).exactly(:once)
          .and not_have_enqueued_job(SendWebhookJob).with("plan.updated", anything)
      end

      it "produces one `plan_entitlement.updated` activity log with the values before and after, and no `plan.updated`" do
        result

        expect(Utils::ActivityLog).to have_received(:produce).with(
          entitlement, "plan_entitlement.updated", after_commit: true,
          changes: {
            "values" => [
              [{privilege_code: "max_admins", value: "test_value"}, {privilege_code: "max", value: "test_value"}],
              [{privilege_code: "max_admins", value: "test_value"}]
            ]
          },
          activity_object: hash_including(lago_id: entitlement.id, values: [{privilege_code: "max_admins", value: "test_value"}])
        ).once
        expect(Utils::ActivityLog).to have_received(:produce).once
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
          expect(entitlement_value.reload).not_to be_discarded
          expect(Utils::ActivityLog).not_to have_received(:produce)
        end
      end

      context "when privilege code does not exist" do
        let(:privilege_code) { "nonexistent" }

        it "returns a not found privilege failure and sends no webhook" do
          expect { result }.not_to have_enqueued_job(SendWebhookJob)
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.resource).to eq("privilege")
          expect(entitlement_value.reload).not_to be_discarded
        end
      end

      context "when the service is called again with the same entitlement" do
        before do
          entitlement.values.load
          described_class.call!(entitlement:, privilege_code:)
        end

        it "returns a not found privilege failure and sends no second webhook" do
          expect { result }.not_to have_enqueued_job(SendWebhookJob)
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.resource).to eq("privilege")
          expect(result.entitlement).to be_nil
        end
      end

      context "when the entitlement was discarded after it was loaded" do
        before do
          Entitlement::Entitlement.where(id: entitlement.id).update_all(deleted_at: Time.current, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
        end

        it "returns a not found privilege failure, discards nothing and sends no webhook" do
          expect { result }.not_to have_enqueued_job(SendWebhookJob)
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.resource).to eq("privilege")
          expect(result.entitlement).to be_nil
          expect(entitlement_value.reload).not_to be_discarded
        end
      end
    end

    context "when entitlement is nil" do
      subject(:result) { described_class.call(entitlement: nil, privilege_code: privilege_code) }

      it "returns not found failure" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("entitlement_not_found")
      end
    end

    context "when privilege code does not exist" do
      let(:privilege_code) { "nonexistent" }

      it "returns not found failure" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("privilege_not_found")
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
            described_class.call(entitlement: Entitlement::Entitlement.find(entitlement_id), privilege_code:)
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

      it "waits for the plan lock, then deletes the privilege value" do
        holder = hold_plan_lock(plan.id)
        locked.pop

        destroyer = destroy(entitlement.id)
        expect(destroyer.join(0.5)).to be_nil
        expect(Entitlement::EntitlementValue.where(id: entitlement_value.id)).to exist

        release << ->(_) {}
        holder.join
        expect(destroyer.value).to be_success
        expect(Entitlement::EntitlementValue.where(entitlement:).pluck(:id)).to eq([entitlement_value2.id])
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
        expect(failure.error.resource).to eq("privilege")
        expect(Entitlement::EntitlementValue.where(entitlement:).pluck(:id)).to eq([entitlement_value2.id])
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
        expect(Entitlement::EntitlementValue.where(id: entitlement_value.id)).to exist
      end
    end

    context "with a catalog plan entitlement and threads", transaction: false do
      let(:catalog_plan) { create(:catalog_plan, organization:) }
      let(:entitlement) { create(:entitlement, :catalog_plan, organization:, catalog_plan:, feature:) }
      let(:locked) { Queue.new }
      let(:release) { Queue.new }

      # Frees a lock holder left waiting by a failed expectation.
      after { release << ->(_) {} }

      # Under the query cache, as a request runs: the reads under the lock must not come from it.
      def destroy(entitlement_id)
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ApplicationRecord.cache do
              described_class.call(entitlement: Entitlement::Entitlement.find(entitlement_id), privilege_code:)
            end
          end
        end
      end

      def hold_catalog_plan_lock(catalog_plan_id)
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ActiveRecord::Base.transaction do
              locked_plan = CatalogPlan.lock("FOR NO KEY UPDATE").find(catalog_plan_id)
              locked << true
              release.pop.call(locked_plan)
            end
          end
        end
      end

      it "waits for the catalog plan lock, then deletes the privilege value" do
        holder = hold_catalog_plan_lock(catalog_plan.id)
        locked.pop

        destroyer = destroy(entitlement.id)
        expect(destroyer.join(0.5)).to be_nil
        expect(Entitlement::EntitlementValue.where(id: entitlement_value.id)).to exist

        release << ->(_) {}
        holder.join
        expect(destroyer.value).to be_success
        expect(Entitlement::EntitlementValue.where(entitlement:).pluck(:id)).to eq([entitlement_value2.id])
      end

      it "answers not found privilege to a delete whose value was removed while it waited for the lock" do
        holder = hold_catalog_plan_lock(catalog_plan.id)
        locked.pop

        destroyer = destroy(entitlement.id)
        expect(destroyer.join(0.5)).to be_nil

        release << ->(_) { Entitlement::EntitlementValue.where(id: entitlement_value.id).update_all(deleted_at: Time.current, updated_at: Time.current) } # rubocop:disable Rails/SkipsModelValidations
        holder.join
        result = destroyer.value

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("privilege")
        expect(result.entitlement).to be_nil
        expect(Entitlement::EntitlementValue.where(entitlement:).pluck(:id)).to eq([entitlement_value2.id])
      end

      it "answers not found privilege to a delete whose entitlement was removed while it waited for the lock" do
        holder = hold_catalog_plan_lock(catalog_plan.id)
        locked.pop

        destroyer = destroy(entitlement.id)
        expect(destroyer.join(0.5)).to be_nil

        release << ->(_) { Entitlement::Entitlement.where(id: entitlement.id).update_all(deleted_at: Time.current, updated_at: Time.current) } # rubocop:disable Rails/SkipsModelValidations
        holder.join
        result = destroyer.value

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("privilege")
        expect(result.entitlement).to be_nil
        expect(Entitlement::EntitlementValue.where(id: entitlement_value.id)).to exist
      end
    end

    context "when entitlement value is already deleted" do
      before do
        entitlement_value.discard!
      end

      it "returns not found failure" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("privilege_not_found")
      end
    end
  end
end
