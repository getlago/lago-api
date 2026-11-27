# frozen_string_literal: true

module DatabaseMigrations
  class BackfillEntitlementBooleanValuesJob < ApplicationJob
    queue_as :low_priority
    unique :until_executed, on_conflict: :log, lock_ttl: 30.minutes

    # ApplicationJob sets retry: 0. The chain is self-terminating, so one failed batch
    # would silently end the whole backfill.
    sidekiq_options retry: 5

    BATCH_SIZE = 5_000

    def perform(cursor = nil)
      ids = next_ids(cursor)
      return finalize if ids.empty?

      Entitlement::EntitlementValue::LEGACY_BOOLEANS.each do |stored, word|
        pending_values.where(id: ids, value: stored)
          .update_all(value: word, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      end

      return self.class.perform_later(ids.last) if ids.size == BATCH_SIZE

      finalize
    end

    def lock_key_arguments
      [arguments]
    end

    private

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

    def finalize
      unless pending_values.exists?
        Rails.logger.info("Finished backfilling boolean entitlement values")
        return
      end

      Rails.logger.error("Boolean entitlement values backfill finished with values still stored as t or f")
      Sentry.capture_message("Boolean entitlement values backfill finished with values still stored as t or f", level: :error)
    end
  end
end
