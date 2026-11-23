# frozen_string_literal: true

module BillingEngineMigrations
  # Hot paths ask this on every request, event and callback: each process keeps the few migration
  # rows in memory, so organizations without a migration cost no query and no cache round trip.
  class Lookup
    REFRESH_INTERVAL = 60.seconds

    Entry = Data.define(:id, :organization_id, :shadow_organization_id, :status, :plan_mapping) do
      def shadowing?
        status == BillingEngineMigration::STATUSES[:shadowing]
      end

      def paused?
        status == BillingEngineMigration::STATUSES[:paused]
      end
    end

    Snapshot = Data.define(:by_source, :by_shadow, :expires_at) do
      def fresh?
        Time.current < expires_at
      end
    end

    SNAPSHOT = Concurrent::AtomicReference.new
    REFRESH_LOCK = Mutex.new

    class << self
      def for_source(organization_id)
        entry = snapshot.by_source[organization_id]
        entry if entry&.shadowing?
      end

      def for_shadow(organization_id)
        snapshot.by_shadow[organization_id]
      end

      def shadow_organization?(organization_id)
        !for_shadow(organization_id).nil?
      end

      def expire!
        REFRESH_LOCK.synchronize { SNAPSHOT.set(nil) }
      end

      private

      def snapshot
        current = SNAPSHOT.get
        return current if current&.fresh?

        REFRESH_LOCK.synchronize do
          current = SNAPSHOT.get
          current&.fresh? ? current : SNAPSHOT.set(load_snapshot)
        end
      end

      def load_snapshot
        entries = BillingEngineMigration
          .where.not(status: BillingEngineMigration::STATUSES[:aborted])
          .pluck(:id, :organization_id, :shadow_organization_id, :status, :plan_mapping)
          .map { |row| build_entry(*row) }

        Snapshot.new(
          by_source: entries.index_by(&:organization_id).freeze,
          by_shadow: entries.index_by(&:shadow_organization_id).freeze,
          expires_at: REFRESH_INTERVAL.from_now
        )
      end

      def build_entry(id, organization_id, shadow_organization_id, status, plan_mapping)
        Entry.new(id:, organization_id:, shadow_organization_id:, status:, plan_mapping: plan_mapping.each_value(&:freeze).freeze)
      end
    end
  end
end
