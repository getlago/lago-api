# frozen_string_literal: true

module Types
  module RatePhases
    class ReplaceInput < BaseInputObject
      description "Replace the whole ordered rate phase sequence of a plan product item"

      argument :plan_rate_card_id, ID, required: true
      argument :rate_phases, [Types::RatePhases::PhaseInput], required: true
    end
  end
end
