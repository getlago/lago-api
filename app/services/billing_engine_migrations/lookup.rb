# frozen_string_literal: true

module BillingEngineMigrations
  # Hot paths ask this on every request, event and callback: each process keeps the few migration
  # rows in memory, so organizations without a migration cost no query and no cache round trip.
  class Lookup
    REFRESH_INTERVAL = 60.seconds
    RETRY_INTERVAL = 5.seconds

    Entry = Data.define(:id, :organization_id, :shadow_organization_id, :status, :plan_mapping, :v2_read_endpoints) do
      def shadowing?
        status == BillingEngineMigration::STATUSES[:shadowing]
      end

      def paused?
        status == BillingEngineMigration::STATUSES[:paused]
      end

      def serves_v2_reads?(endpoint)
        v2_read_endpoints.include?(endpoint)
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

        if current.nil?
          REFRESH_LOCK.synchronize { reload }
        else
          reload_unless_another_thread_does(current)
        end
      end

      def reload_unless_another_thread_does(stale)
        if REFRESH_LOCK.try_lock
          begin
            reload
          ensure
            REFRESH_LOCK.unlock
          end
        else
          stale
        end
      end

      def reload
        current = SNAPSHOT.get
        current&.fresh? ? current : SNAPSHOT.set(load_snapshot)
      rescue ActiveRecord::ActiveRecordError => e
        raise if current.nil?

        Rails.logger.error("[billing_engine_migrations] lookup reload failed, serving the stale snapshot: #{e.class} #{e.message}")
        SNAPSHOT.set(current.with(expires_at: RETRY_INTERVAL.from_now))
      end

      def load_snapshot
        entries = BillingEngineMigration
          .where.not(status: BillingEngineMigration::STATUSES[:aborted])
          .pluck(:id, :organization_id, :shadow_organization_id, :status, :plan_mapping, :v2_read_endpoints)
          .map { |row| build_entry(*row) }

        Snapshot.new(
          by_source: entries.index_by(&:organization_id).freeze,
          by_shadow: entries.index_by(&:shadow_organization_id).freeze,
          expires_at: REFRESH_INTERVAL.from_now
        )
      end

      def build_entry(id, organization_id, shadow_organization_id, status, plan_mapping, v2_read_endpoints)
        Entry.new(
          id:,
          organization_id:,
          shadow_organization_id:,
          status:,
          plan_mapping: plan_mapping.each_value(&:freeze).freeze,
          v2_read_endpoints: v2_read_endpoints.each(&:freeze).freeze
        )
      end
    end
  end
end
