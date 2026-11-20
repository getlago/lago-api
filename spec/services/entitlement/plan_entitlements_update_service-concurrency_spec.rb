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

      def write(plan_id, feature_code, privilege_code, value, plan_record: nil, partial: true)
        write_params(plan_id, {feature_code => {privilege_code => value}}, plan_record:, partial:)
      end

      def write_params(plan_id, entitlements_params, plan_record: nil, partial: true)
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            described_class.call(
              organization: Organization.find(organization.id),
              plan: plan_record || Plan.find(plan_id),
              entitlements_params:,
              partial:
            )
          end
        end
      end

      # Runs the block in another connection once the writer holds the plan lock, before it locks the features.
      def after_plan_lock(plan_record, &block)
        allow(plan_record).to receive(:lock!).and_wrap_original do |original, *args|
          original.call(*args).tap do
            Thread.new { ActiveRecord::Base.connection_pool.with_connection(&block) }.join(5)
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

      # The writer has read the feature when it reaches the insert. The delete runs from another connection
      # there, given a bounded time: it either commits first, or waits for the writer and discards what it wrote.
      it "leaves no live entitlement on a feature deleted while a write adds it" do
        feature_id = feature.id
        deleter = nil

        allow(Entitlement::Entitlement).to receive(:create!).and_wrap_original do |original, *args, **kwargs|
          deleter ||= Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              Entitlement::FeatureDestroyService.call(feature: Entitlement::Feature.find(feature_id))
            end
          end
          deleter.join(1)
          original.call(*args, **kwargs)
        end

        writer = write(plan.id, feature.code, privilege.code, 20)
        expect(writer.join(5)).to eq(writer)
        expect(deleter.join(5)).to eq(deleter)

        expect(deleter.value).to be_success
        expect(Entitlement::Feature.with_discarded.find(feature_id)).to be_discarded
        expect(Entitlement::Entitlement.where(entitlement_feature_id: feature_id).count).to eq(0)
        expect(Entitlement::EntitlementValue.where(entitlement_privilege_id: privilege.id).count).to eq(0)
      end

      # The writer holds the feature lock when it reaches the insert, after it read the feature. The delete starts
      # there and must wait for the writer to commit, then discards what it wrote.
      it "makes a feature delete wait for a write that read the feature" do
        feature_id = feature.id
        deleter = nil
        blocked = Queue.new

        allow(Entitlement::Entitlement).to receive(:create!).and_wrap_original do |original, *args, **kwargs|
          deleter ||= Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              Entitlement::FeatureDestroyService.call(feature: Entitlement::Feature.find(feature_id))
            end
          end
          blocked << deleter.join(0.5).nil?
          original.call(*args, **kwargs)
        end

        writer = write(plan.id, feature.code, privilege.code, 20)
        expect(writer.join(5)).to eq(writer)
        expect(deleter.join(5)).to eq(deleter)

        expect(blocked.pop(timeout: 1)).to be(true)
        expect(writer.value).to be_success
        expect(deleter.value).to be_success
        expect(Entitlement::Entitlement.where(entitlement_feature_id: feature_id).count).to eq(0)
        expect(Entitlement::EntitlementValue.where(entitlement_privilege_id: privilege.id).count).to eq(0)
      end

      it "refuses a write adding a feature deleted after it locked the plan" do
        feature_id = feature.id
        plan_record = Plan.find(plan.id)
        deleted = Queue.new
        after_plan_lock(plan_record) do
          deleted << Entitlement::FeatureDestroyService.call(feature: Entitlement::Feature.find(feature_id))
        end

        writer = write(plan.id, feature.code, privilege.code, 20, plan_record:)
        expect(writer.join(5)).to eq(writer)
        result = writer.value

        expect(deleted.pop(timeout: 1)).to be_success
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("feature")
        expect(Entitlement::Entitlement.where(entitlement_feature_id: feature_id).count).to eq(0)
        expect(Entitlement::EntitlementValue.where(entitlement_privilege_id: privilege.id).count).to eq(0)
        expect(SendWebhookJob).not_to have_been_enqueued.with("plan.updated", anything)
      end

      it "keeps the entitlements of a full replace that loses the race to a feature delete" do
        extra_entitlement = create(:entitlement, organization:, plan:, feature: other_feature)
        feature_id = feature.id
        plan_record = Plan.find(plan.id)
        deleted = Queue.new
        after_plan_lock(plan_record) do
          deleted << Entitlement::FeatureDestroyService.call(feature: Entitlement::Feature.find(feature_id))
        end

        writer = write(plan.id, feature.code, privilege.code, 20, plan_record:, partial: false)
        expect(writer.join(5)).to eq(writer)
        result = writer.value

        expect(deleted.pop(timeout: 1)).to be_success
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("feature")
        expect(extra_entitlement.reload.deleted_at).to be_nil
        expect(Entitlement::Entitlement.where(entitlement_feature_id: feature_id).count).to eq(0)
        expect(SendWebhookJob).not_to have_been_enqueued.with("plan.updated", anything)
      end

      # The writer holds the feature when it reaches the value insert. The privilege delete runs from another
      # connection there, given a bounded time: it either commits first, or waits for the writer and discards its value.
      # The entitlement exists already: inserting it would key-share lock the feature and make the delete wait anyway.
      it "leaves no live value on a privilege deleted while a write sets it" do
        create(:entitlement, organization:, plan:, feature:)
        privilege_id = privilege.id
        deleter = nil

        allow(Entitlement::EntitlementValue).to receive(:create!).and_wrap_original do |original, *args, **kwargs|
          deleter ||= Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              Entitlement::PrivilegeDestroyService.call(privilege: Entitlement::Privilege.find(privilege_id))
            end
          end
          deleter.join(1)
          original.call(*args, **kwargs)
        end

        writer = write(plan.id, feature.code, privilege.code, 20)
        expect(writer.join(5)).to eq(writer)
        expect(deleter.join(5)).to eq(deleter)

        expect(writer.value).to be_success
        expect(deleter.value).to be_success
        expect(Entitlement::Privilege.with_discarded.find(privilege_id)).to be_discarded
        expect(Entitlement::EntitlementValue.where(entitlement_privilege_id: privilege_id).count).to eq(0)
      end

      it "refuses a write setting a value on a privilege deleted after it locked the plan" do
        privilege_id = privilege.id
        plan_record = Plan.find(plan.id)
        deleted = Queue.new
        after_plan_lock(plan_record) do
          deleted << Entitlement::PrivilegeDestroyService.call(privilege: Entitlement::Privilege.find(privilege_id))
        end

        writer = write(plan.id, feature.code, privilege.code, 20, plan_record:)
        expect(writer.join(5)).to eq(writer)
        result = writer.value

        expect(deleted.pop(timeout: 1)).to be_success
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("privilege")
        expect(Entitlement::Entitlement.where(plan_id: plan.id).count).to eq(0)
        expect(Entitlement::EntitlementValue.where(entitlement_privilege_id: privilege_id).count).to eq(0)
      end

      # Each writer holds the shared feature lock when it reaches the insert, and waits there, for a bounded time,
      # for the other one: both arrive only when neither lock blocks the other.
      it "lets two writes on two plans add the same feature without waiting for each other" do
        arrived = Queue.new
        met = Queue.new

        allow(Entitlement::Entitlement).to receive(:create!).and_wrap_original do |original, *args, **kwargs|
          arrived << true
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
          sleep 0.05 while arrived.size < 2 && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
          met << (arrived.size >= 2)
          original.call(*args, **kwargs)
        end

        results = [
          write(plan.id, feature.code, privilege.code, 10),
          write(other_plan.id, feature.code, privilege.code, 20)
        ].map { it.join(5).value }

        expect(results).to all(be_success)
        expect(Array.new(met.size) { met.pop }).to eq([true, true])
        expect(Entitlement::Entitlement.where(entitlement_feature_id: feature.id).group(:plan_id).count)
          .to eq(plan.id => 1, other_plan.id => 1)
      end

      # Each writer waits at its first insert, for a bounded time, for the other one, so both hold their feature
      # locks at the same time. The features are locked by id whatever the order of the params.
      it "does not deadlock when two writes lock the same two features in opposite param order" do
        arrived = Queue.new

        allow(Entitlement::Entitlement).to receive(:create!).and_wrap_original do |original, *args, **kwargs|
          arrived << true
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
          sleep 0.05 while arrived.size < 2 && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
          original.call(*args, **kwargs)
        end

        writers = [
          write_params(plan.id, {feature.code => {privilege.code => 10}, other_feature.code => {other_privilege.code => 10}}),
          write_params(other_plan.id, {other_feature.code => {other_privilege.code => 20}, feature.code => {privilege.code => 20}})
        ]

        expect(writers.map { it.join(5) }).to eq(writers)
        expect(writers.map(&:value)).to all(be_success)
        expect(Entitlement::Entitlement.where(plan_id: [plan.id, other_plan.id]).group(:plan_id).count)
          .to eq(plan.id => 2, other_plan.id => 2)
      end
    end
  end
end
