# frozen_string_literal: true

module BillingEngineMigrations
  # The V1 subscriptions whose events are copied to the shadow organization: active, on a mapped
  # plan and not on an override. Each process keeps their external ids per migration for a few
  # minutes. An id missing from that snapshot is looked up once, so a subscription created since is
  # found on its first event, and an unmapped one costs a query once per refresh, not per event.
  class MappedSubscriptions
    REFRESH_INTERVAL = 5.minutes

    Snapshot = Data.define(:plan_mapping, :plan_ids, :mapped, :unmapped, :expires_at) do
      def current_for?(migration)
        Time.current < expires_at && plan_mapping == migration.plan_mapping
      end

      def known?(external_id)
        mapped.key?(external_id) || unmapped.key?(external_id)
      end
    end

    SNAPSHOTS = Concurrent::Map.new

    class << self
      def filter(migration, external_ids)
        snapshot = snapshot_for(migration)
        resolve(migration, snapshot, external_ids.uniq.reject { snapshot.known?(it) })

        external_ids.select { snapshot.mapped.key?(it) }.to_set
      end

      def expire!
        SNAPSHOTS.clear
      end

      private

      def snapshot_for(migration)
        current = SNAPSHOTS[migration.id]
        return current if current&.current_for?(migration)

        SNAPSHOTS.compute(migration.id) do |latest|
          latest&.current_for?(migration) ? latest : load_snapshot(migration)
        end
      end

      def load_snapshot(migration)
        plan_ids = mapped_plan_ids(migration)

        Snapshot.new(
          plan_mapping: migration.plan_mapping,
          plan_ids:,
          mapped: id_set(active_subscriptions(migration, plan_ids).distinct.pluck(:external_id)),
          unmapped: Concurrent::Map.new,
          expires_at: REFRESH_INTERVAL.from_now
        )
      end

      def resolve(migration, snapshot, unknown_ids)
        return if unknown_ids.empty?

        found = active_subscriptions(migration, snapshot.plan_ids).where(external_id: unknown_ids).distinct.pluck(:external_id)
        found.each { snapshot.mapped[it] = true }
        (unknown_ids - found).each { snapshot.unmapped[it] = true }
      end

      def mapped_plan_ids(migration)
        Plan.where(organization_id: migration.organization_id, code: migration.plan_mapping.keys, parent_id: nil).pluck(:id)
      end

      def active_subscriptions(migration, plan_ids)
        return Subscription.none if plan_ids.empty?

        Subscription.active.where(organization_id: migration.organization_id, plan_id: plan_ids)
      end

      def id_set(external_ids)
        external_ids.each_with_object(Concurrent::Map.new) { |external_id, set| set[external_id] = true }
      end
    end
  end
end
