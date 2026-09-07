# frozen_string_literal: true

module DatabaseMigrations
  class BackfillChargeFilterCodesJob < ApplicationJob
    queue_as :low_priority
    unique :until_executed, on_conflict: :log, lock_ttl: 6.hours

    def perform(charge_id)
      charge = Charge.kept.includes(:plan).find_by(id: charge_id)

      return if charge.nil?
      return unless charge.parent_id.nil? && charge.plan.parent_id.nil?

      filters = charge.filters.includes(values: :billable_metric_filter).to_a
      taken = filters.filter_map(&:code).to_set

      # Grouped by the code the values derive rather than by the values, since the code is what can
      # collide: it sorts, so `{region: [us, eu]}` and `{region: [eu, us]}` are the same
      filters.group_by { ChargeFilter.generate_code(it.to_h) }.each do |code, group|
        next unless group.one?       # skip duplicates
        next if group.sole.code      # already have code
        next if taken.include?(code) # already taken ( would generate duplicate )

        group.sole.update_column(:code, code) # rubocop:disable Rails/SkipsModelValidations
      end

      return unless filters.any?(&:code)

      BackfillChildChargeFilterCodesJob.perform_later(charge.id)
    end

    def lock_key_arguments
      [arguments]
    end
  end
end
