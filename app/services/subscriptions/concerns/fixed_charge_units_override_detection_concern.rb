# frozen_string_literal: true

module Subscriptions
  module Concerns
    # Pure params-shape predicates that decide whether a request is eligible
    # for the units-only override write path (writing one row to
    # subscription_fixed_charge_units_overrides instead of cloning the plan).
    #
    # The two shapes handled here:
    #
    # - `plan_overrides` envelope (subscription create/update with
    #   `plan_overrides.fixed_charges`): match when only the `fixed_charges`
    #   key is present, the array is non-empty, and every entry contains only
    #   `id`, `units`, and optionally `apply_units_immediately`.
    # - Dedicated subscription-scoped fixed_charge endpoint
    #   (`UpdateOrOverrideFixedChargeService`): match when the top-level
    #   params contain `units` and optionally `apply_units_immediately`, and
    #   nothing else (the fixed_charge identity comes from the URL).
    #
    # The cloned-plan guard (`subscription.plan.parent_id` is set) is
    # enforced by each calling service against the subscription it holds,
    # not here — these predicates only inspect params.
    module FixedChargeUnitsOverrideDetectionConcern
      extend ActiveSupport::Concern

      PLAN_OVERRIDES_FIXED_CHARGE_ALLOWED_KEYS = %i[id units apply_units_immediately].freeze
      DEDICATED_ENDPOINT_ALLOWED_KEYS = %i[units apply_units_immediately].freeze

      private

      def units_only_fixed_charges_plan_overrides?(plan_overrides)
        plan_overrides = normalize_hash(plan_overrides)
        return false unless plan_overrides
        return false unless plan_overrides.keys == [:fixed_charges]

        fixed_charges = plan_overrides[:fixed_charges]
        return false unless fixed_charges&.any?

        fixed_charges.all? { |entry| units_only_fixed_charges_entry?(entry) }
      end

      def units_only_fixed_charge_params?(params)
        params = normalize_hash(params)
        return false unless params
        return false unless params.key?(:units)

        (params.keys - DEDICATED_ENDPOINT_ALLOWED_KEYS).empty?
      end

      def units_only_fixed_charges_entry?(entry)
        entry = normalize_hash(entry)
        return false unless entry
        return false unless entry.key?(:id) && entry.key?(:units)

        (entry.keys - PLAN_OVERRIDES_FIXED_CHARGE_ALLOWED_KEYS).empty?
      end

      def normalize_hash(value)
        return nil if value.nil?
        return value.symbolize_keys if value.is_a?(Hash)
        return value.to_h.symbolize_keys if value.respond_to?(:to_h)

        nil
      end
    end
  end
end
