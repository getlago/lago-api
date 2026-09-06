# frozen_string_literal: true

# Vendored verbatim from app/services/subscription_rate_cards/resolve_rate_phases_service.rb.
# Only the `RatePhases` value object is vendored: the engine never calls the service
# itself, it only receives a RatePhases and calls `rate_phase_for_cycle`.
module LegacyEngine; end

module LegacyEngine::SubscriptionRateCards
  class ResolveRatePhasesService
    RatePhases = Data.define(:phases) do
      def rate_phase_for_cycle(cycle_index)
        cursor = 0

        phases.each do |phase|
          count = phase.billing_interval_cycle_count
          return phase if count.nil?

          cursor += count
          return phase if cycle_index < cursor
        end

        nil
      end
    end
  end
end
