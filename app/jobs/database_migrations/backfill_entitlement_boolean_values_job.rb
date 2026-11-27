# frozen_string_literal: true

module DatabaseMigrations
  class BackfillEntitlementBooleanValuesJob < ApplicationJob
    queue_as :low_priority
    # The lock is keyed on the job arguments, as the Sidekiq death handler unlocks it: a dead batch can be resumed.
    unique :until_executed, on_conflict: :log, lock_ttl: 30.minutes

    # ApplicationJob sets retry: 0. The chain is self-terminating, so one failed batch
    # would silently end the whole backfill.
    sidekiq_options retry: 5

    BATCH_SIZE = 5_000
    # The second pass rewrites the rows a request held during the first one, and those written behind the cursor.
    MAX_PASSES = 2

    def perform(cursor = nil, pass = 1)
      ids = next_ids(cursor)
      return finalize(pass) if ids.empty?

      rewrite(ids)

      if ids.size == BATCH_SIZE
        self.class.perform_later(ids.last, pass)
      else
        finalize(pass)
      end
    end

    private

    # Rows a request holds are skipped, not waited on, so that the job never takes part in a deadlock.
    def rewrite(ids)
      Entitlement::EntitlementValue::LEGACY_BOOLEANS.each do |stored, word|
        unlocked = pending_values.where(id: ids, value: stored).lock("FOR UPDATE SKIP LOCKED").select(:id)

        Entitlement::EntitlementValue.unscoped.where(id: unlocked)
          .update_all(value: word, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      end
    end

    def next_ids(cursor)
      scope = pending_values.order(:id).limit(BATCH_SIZE)
      scope = scope.where("entitlement_entitlement_values.id > ?", cursor) if cursor

      scope.ids
    end

    def pending_values
      Entitlement::EntitlementValue.unscoped
        .where(value: Entitlement::EntitlementValue::LEGACY_BOOLEANS.keys)
        .where(entitlement_privilege_id: Entitlement::Privilege.unscoped.where(value_type: "boolean").select(:id))
    end

    def finalize(pass)
      unless pending_values.exists?
        Rails.logger.info("Finished backfilling boolean entitlement values")
        return
      end

      if pass < MAX_PASSES
        self.class.perform_later(nil, pass + 1)
      else
        Rails.logger.error("Boolean entitlement values backfill finished with values still stored as t or f")
        Sentry.capture_message("Boolean entitlement values backfill finished with values still stored as t or f", level: :error)
      end
    end
  end
end
