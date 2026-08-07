# frozen_string_literal: true

module DatabaseMigrations
  class BackfillChargeFilterCodesJob < ApplicationJob
    queue_as :low_priority
    unique :until_executed

    def perform(charge_id)
      charge = Charge.kept.includes(:plan).find_by(id: charge_id)
      return if charge.nil?

      # Both, as the service requires when it picks them. `charges.parent_id` goes back to NULL
      # when the parent charge is deleted (has_many :children, dependent: :nullify), so on its
      # own it cannot tell a plan's charge from an override that lost its parent — and a charge
      # that does carry one is a copy, whose code has to be inherited rather than derived
      return unless charge.parent_id.nil? && charge.plan.parent_id.nil?

      filters = charge.filters.includes(values: :billable_metric_filter).to_a

      codes = filters.to_h { [it.id, it.code || ChargeFilter.generate_code(it.to_h)] }

      # Only the filters that are not duplicated receive code
      shared = codes.values.tally.select { |_, count| count > 1 }.keys.to_set

      filters.each do |filter|
        next if filter.code || shared.include?(codes[filter.id])

        filter.update_column(:code, codes[filter.id]) # rubocop:disable Rails/SkipsModelValidations
      end
    end

    def lock_key_arguments
      [arguments]
    end
  end
end
