# frozen_string_literal: true

# Shared by the two rate-phase parents (plan_rate_card and
# subscription_rate_card): walking the ordered phase sequence to find the
# one covering a billing cycle.
module RatePhaseable
  extend ActiveSupport::Concern

  # Returns the rate phase covering the given zero-based billing cycle index.
  # Phases (ordered by position) partition the timeline by their cumulative
  # billing_interval_cycle_count; the final phase may carry a nil count,
  # meaning it runs indefinitely. Returns nil when no phase covers the cycle.
  def rate_phase_for_cycle(cycle_index)
    cursor = 0

    rate_phases.order(:position).each do |phase|
      count = phase.billing_interval_cycle_count
      return phase if count.nil?

      cursor += count
      return phase if cycle_index < cursor
    end

    nil
  end
end
