# frozen_string_literal: true

module DatabaseMigrations
  class BackfillChildChargeFilterCodesJob < ApplicationJob
    queue_as :low_priority
    unique :until_executed, on_conflict: :log, lock_ttl: 6.hours

    CHARGES_PER_BATCH = 1_000
    IDS_PER_UPDATE = 10_000

    # One row per charge filter, filled positionally from the `pluck` in `filters_of`
    Filter = Data.define(:charge_id, :id, :code, :signature)

    SIGNATURE_SQL = <<~SQL.squish
      COALESCE(
        jsonb_object_agg(
          cfv.billable_metric_filter_id,
          to_jsonb(ARRAY(SELECT unnest(cfv.values) ORDER BY 1))
        ) FILTER (WHERE cfv.id IS NOT NULL),
        '{}'::jsonb
      )::text
    SQL

    def perform(parent_charge_id)
      parent = Charge.kept.includes(:plan).find_by(id: parent_charge_id)
      return if parent.nil?

      return unless parent.parent_id.nil? && parent.plan.parent_id.nil?

      to_copy = codes_to_copy(parent)
      return if to_copy.empty?

      parent.children.in_batches(of: CHARGES_PER_BATCH) do |children|
        backfill(children, to_copy)
      end
    end

    def lock_key_arguments
      [arguments]
    end

    private

    # The codes this parent can hand down (without duplicates)
    def codes_to_copy(parent)
      codes = {}

      filters_of(parent.id).group_by(&:signature).each do |signature, filters|
        next unless filters.one?
        next if filters.sole.code.nil? # no code yet: nothing to hand down

        codes[signature] = filters.sole.code
      end

      codes
    end

    # Walks what the parent has to hand down rather than the override's filters, so one the override
    # has and the plan does not is never visited, and keeps no code.
    def backfill(children, to_copy)
      ids_by_code = Hash.new { |ids, code| ids[code] = [] }

      filters_of(children).group_by(&:charge_id).each_value do |filters|
        by_signature = filters.group_by(&:signature)
        taken = filters.filter_map(&:code).to_set

        to_copy.each do |signature, code|
          next if taken.include?(code) # a filter here already holds it, from when its values were these

          matching = by_signature[signature]
          next unless matching&.one? # held twice here: neither can say which one is the copy
          next if matching.sole.code # frozen at creation, and that is the one it keeps

          ids_by_code[code] << matching.sole.id
        end
      end

      write_codes(ids_by_code)
    end

    # One query for a whole batch of charges, filters and values and all
    def filters_of(charge_scope)
      ChargeFilter
        .where(charge_id: charge_scope)
        .joins("LEFT JOIN charge_filter_values cfv ON cfv.charge_filter_id = charge_filters.id AND cfv.deleted_at IS NULL")
        .group("charge_filters.id")
        .pluck(:charge_id, :id, :code, Arel.sql(SIGNATURE_SQL))
        .map { Filter.new(*it) }
    end

    # One statement per code
    def write_codes(ids_by_code)
      ids_by_code.each do |code, ids|
        ids.each_slice(IDS_PER_UPDATE) do |slice|
          ChargeFilter.where(id: slice, code: nil).update_all(code:) # rubocop:disable Rails/SkipsModelValidations
        end
      end
    end
  end
end
