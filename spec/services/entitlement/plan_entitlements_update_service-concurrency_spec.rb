# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::PlanEntitlementsUpdateService do
  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:feature) { create(:feature, organization:) }
  let(:privilege) { create(:privilege, feature:, code: "max", value_type: "integer") }

  describe "#call", :premium do
    # Both writers must have read the plan entitlements before either inserts. Each one waits at the insert
    # for the other to arrive, for a bounded time, so a writer serialized behind the other does not hang.
    it "serializes two concurrent writes adding the same feature on one plan", transaction: false do
      plan_id = plan.id
      organization_id = organization.id
      privilege_code = privilege.code
      feature_code = feature.code
      feature_id = feature.id
      arrived = Queue.new

      allow(Entitlement::Entitlement).to receive(:create!).and_wrap_original do |original, *args, **kwargs|
        arrived << true
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
        sleep 0.05 while arrived.size < 2 && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        original.call(*args, **kwargs)
      end

      results = [10, 20].map do |value|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            described_class.call(
              organization: Organization.find(organization_id),
              plan: Plan.find(plan_id),
              entitlements_params: {feature_code => {privilege_code => value}},
              partial: true
            )
          end
        end
      end.map(&:value)

      expect(results).to all(be_success)
      expect(Entitlement::Entitlement.where(plan_id:, entitlement_feature_id: feature_id).count).to eq(1)
    end

    context "with threads", transaction: false do
      let(:other_plan) { create(:plan, organization:) }
      let(:other_feature) { create(:feature, organization:) }
      let(:other_privilege) { create(:privilege, feature: other_feature, code: "max", value_type: "integer") }
      let(:locked) { Queue.new }
      let(:release) { Queue.new }

      before do
        privilege
        other_privilege
      end

      # Frees a lock holder left waiting by a failed expectation.
      after { release << ->(_) {} }

      def write(plan_id, feature_code, privilege_code, value)
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            described_class.call(
              organization: Organization.find(organization.id),
              plan: Plan.find(plan_id),
              entitlements_params: {feature_code => {privilege_code => value}},
              partial: true
            )
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

      it "stores two concurrent writes of two different features on one plan" do
        results = [
          write(plan.id, feature.code, privilege.code, 10),
          write(plan.id, other_feature.code, other_privilege.code, 20)
        ].map(&:value)

        expect(results).to all(be_success)
        expect(Entitlement::Entitlement.where(plan_id: plan.id).pluck(:entitlement_feature_id))
          .to match_array([feature.id, other_feature.id])
      end

      it "makes a write on the locked plan wait, and not a write on another plan" do
        holder = hold_plan_lock(plan.id)
        locked.pop

        other_writer = write(other_plan.id, feature.code, privilege.code, 10)
        expect(other_writer.join(5)).to eq(other_writer)
        expect(other_writer.value).to be_success

        writer = write(plan.id, feature.code, privilege.code, 20)
        expect(writer.join(0.5)).to be_nil

        release << ->(_) {}
        holder.join
        expect(writer.value).to be_success
        expect(Entitlement::Entitlement.where(plan_id: plan.id, entitlement_feature_id: feature.id).count).to eq(1)
      end

      it "refuses a write on a plan discarded while it waits for the lock" do
        holder = hold_plan_lock(plan.id)
        locked.pop

        writer = write(plan.id, feature.code, privilege.code, 20)
        expect(writer.join(0.5)).to be_nil

        release << ->(locked_plan) { locked_plan.update_columns(deleted_at: Time.current) } # rubocop:disable Rails/SkipsModelValidations
        holder.join
        result = writer.value

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("plan")
        expect(Entitlement::Entitlement.where(plan_id: plan.id).count).to eq(0)
      end
    end
  end
end
