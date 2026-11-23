# frozen_string_literal: true

module BillingEngineMigrations
  # The V1 subscriptions whose events are copied to the shadow organization: active, on a mapped
  # plan and not on an override. Each process remembers, per migration and for a minute, the ids it
  # found mapped. Unmapped ids are never remembered: a plan change keeps the external id, so one
  # moving onto a mapped plan is copied from its next event.
  class MappedSubscriptions
    REFRESH_INTERVAL = Lookup::REFRESH_INTERVAL

    Snapshot = Data.define(:plan_mapping, :plan_ids, :mapped, :expires_at) do
      def current_for?(migration)
        Time.current < expires_at && plan_mapping == migration.plan_mapping
      end
    end

    SNAPSHOTS = Concurrent::Map.new

    class << self
      def filter(migration, external_ids)
        snapshot = snapshot_for(migration)
        unknown_ids = external_ids.uniq.reject { snapshot.mapped.key?(it) }
        remember_mapped(migration, snapshot, unknown_ids) if unknown_ids.any?

        external_ids.select { snapshot.mapped.key?(it) }.to_set
      end

      def expire!
        SNAPSHOTS.clear
      end

      private

      def snapshot_for(migration)
        current = SNAPSHOTS[migration.id]

        if current&.current_for?(migration)
          current
        else
          SNAPSHOTS[migration.id] = load_snapshot(migration)
        end
      end

      def load_snapshot(migration)
        Snapshot.new(
          plan_mapping: migration.plan_mapping,
          plan_ids: mapped_plan_ids(migration),
          mapped: Concurrent::Map.new,
          expires_at: REFRESH_INTERVAL.from_now
        )
      end

      def remember_mapped(migration, snapshot, external_ids)
        active_subscriptions(migration, snapshot.plan_ids)
          .where(external_id: external_ids)
          .distinct
          .pluck(:external_id)
          .each { snapshot.mapped[it] = true }
      end

      def mapped_plan_ids(migration)
        Plan.where(organization_id: migration.organization_id, code: migration.plan_mapping.keys, parent_id: nil).pluck(:id)
      end

      def active_subscriptions(migration, plan_ids)
        if plan_ids.empty?
          Subscription.none
        else
          Subscription.active.where(organization_id: migration.organization_id, plan_id: plan_ids)
        end
      end
    end
  end
end
