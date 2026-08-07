# frozen_string_literal: true

module DatabaseMigrations
  class BackfillChildChargeFilterCodesJob < ApplicationJob
    queue_as :low_priority
    unique :until_executed

    MAX_FILTERS_PER_BATCH = 20_000

    def perform(parent_charge_id)
      parent = Charge.kept.includes(:plan).find_by(id: parent_charge_id)
      return if parent.nil?
      return unless parent.parent_id.nil? && parent.plan.parent_id.nil?

      codes = parent_codes_by_values(parent)
      return if codes.empty?

      # A local cursor rather than a job argument: the loop lives inside one run, so there is
      # nothing to carry between them. A restart begins the parent again, which is free of
      # consequence since a filter that already has a code is never rewritten.
      cursor = nil
      batch_size = [MAX_FILTERS_PER_BATCH / codes.size, 1].max

      loop do
        children = next_children(parent, cursor, batch_size)
        break if children.empty?

        cursor = children.last.id
        children.each { assign_codes(it, codes) }
      end
    end

    def lock_key_arguments
      [arguments]
    end

    private

    def next_children(parent, cursor, batch_size)
      scope = parent.children.kept
        .includes(filters: {values: :billable_metric_filter})
        .order(:id)
        .limit(batch_size)

      scope = scope.where("charges.id > ?", cursor) if cursor

      scope.to_a
    end

    # Copied from the parent rather than derived from the override's own values. A code is frozen
    # at creation, so a parent whose values moved since holds one its current values no longer
    # produce — deriving would miss it and orphan an override that is not orphaned. It also spares
    # a digest per filter, across nineteen million of them.
    #
    # A predicate the parent holds twice is dropped: it cannot say which of the two an override
    # was copied from, and that is the same question the first pass refused to answer.
    def parent_codes_by_values(parent)
      parent.filters.group_by(&:to_h).filter_map do |values, filters|
        [values, filters.first.code] if filters.one? && filters.first.code
      end.to_h
    end

    def assign_codes(child, available)
      filters = child.filters
      codes = filters.to_h { [it.id, it.code || available[it.to_h]] }

      # Two filters cannot hold the same code, and picking which of them keeps it decides which
      # one bills. Same rule as the parents pass, for the same reason.
      shared = codes.values.compact.tally.select { |_, count| count > 1 }.keys.to_set

      filters.each do |filter|
        code = codes[filter.id]
        next if filter.code || code.nil? || shared.include?(code)

        filter.update_column(:code, code) # rubocop:disable Rails/SkipsModelValidations
      end
    end
  end
end
