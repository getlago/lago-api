# frozen_string_literal: true

module BillingPeriods
  # One slice of a period, priced with a single catalog rate.
  #
  # This is the unit the engine bills: one row for the producer, one fee for the consumer.
  #
  #   billing_at      when it falls due, as its timing defines it — carried rather than
  #                   derived, because a cancelled card bills at the cancellation
  #   consumed_ratio  how much of it was used when service stopped, which the credit for the
  #                   remainder is taken against. Nil unless the run is a cancellation
  Cycle = Data.define(
    :starts_at,
    :ends_at,
    :billing_at,
    :rate,
    :period,
    :proration_ratio,
    :consumed_ratio
  ) do
    delegate :index, to: :period, prefix: true
    delegate :rate_phase, :rate_override, to: :period

    def rate_properties
      (rate_override || rate).properties
    end
  end
end
