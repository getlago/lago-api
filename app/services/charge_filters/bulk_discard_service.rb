# frozen_string_literal: true

module ChargeFilters
  # Discards charge filters together with the values they still hold, in bounded statements.
  # Callers can share a `discarded_at` so one run's rows can be listed, or restored, in a single statement.
  class BulkDiscardService < BaseService
    Result = BaseResult[:discarded_at, :discarded_count]

    BATCH_SIZE = 1_000

    def initialize(charge_filter_ids:, discarded_at: nil)
      @charge_filter_ids = charge_filter_ids
      @discarded_at = discarded_at || Time.current

      super
    end

    def call
      result.discarded_at = discarded_at
      result.discarded_count = 0

      charge_filter_ids.each_slice(BATCH_SIZE) do |ids|
        # rubocop:disable Rails/SkipsModelValidations
        ChargeFilterValue.where(charge_filter_id: ids).unscope(:order).update_all(deleted_at: discarded_at)
        result.discarded_count += ChargeFilter
          .where(id: ids, deleted_at: nil)
          .unscope(:order)
          .update_all(deleted_at: discarded_at)
        # rubocop:enable Rails/SkipsModelValidations
      end

      result
    end

    private

    attr_reader :charge_filter_ids, :discarded_at
  end
end
