# frozen_string_literal: true

module Types
  module RatePhases
    class PhaseInput < BaseInputObject
      description "A single rate phase"

      argument :billing_interval_cycle_count, Integer, required: false
      argument :code, String, required: true
      argument :name, String, required: false
      argument :position, Integer, required: true
      argument :rate_override, Types::RateOverrides::Input, required: false
    end
  end
end
