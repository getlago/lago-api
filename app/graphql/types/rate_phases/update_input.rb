# frozen_string_literal: true

module Types
  module RatePhases
    class UpdateInput < BaseInputObject
      description "Update a single phase, addressed by its code within the entry"

      argument :code, String, required: true
      argument :plan_applied_rate_card_id, ID, required: true

      argument :billing_interval_cycle_count, Integer, required: false
      argument :name, String, required: false
      argument :new_code, String, required: false
      argument :rate_override, Types::RateOverrides::Input, required: false
    end
  end
end
