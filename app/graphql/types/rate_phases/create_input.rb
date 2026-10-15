# frozen_string_literal: true

module Types
  module RatePhases
    class CreateInput < BaseInputObject
      description "Insert a phase into a plan rate card's sequence"

      argument :plan_applied_rate_card_id, ID, required: true

      argument :billing_interval_cycle_count, Integer, required: false
      argument :code, String, required: true
      argument :name, String, required: false
      argument :position, Integer, required: false
      argument :rate_override, Types::RateOverrides::Input, required: false
    end
  end
end
