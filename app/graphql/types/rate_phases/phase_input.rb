# frozen_string_literal: true

module Types
  module RatePhases
    class PhaseInput < BaseInputObject
      description "A single rate phase in a replace-sequence request"

      argument :billing_interval_cycle_count, Integer, required: false
      argument :name, String, required: false
      argument :position, Integer, required: true
    end
  end
end
