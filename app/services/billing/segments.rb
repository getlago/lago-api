# frozen_string_literal: true

module Billing
  module Segments
    Segment = Data.define(:started_at, :ended_at, :rate)

    # Split the half-open window at each rate change, keeping unpriced periods with rate: nil.
    def self.within(window, rates:, starts_at: nil, ends_at: nil)
      started_at = [window.started_at, starts_at].compact.max
      ended_at = [window.ended_at, ends_at].compact.min
      if started_at >= ended_at
        return []
      end

      boundaries = [started_at] + rate_changes_inside(started_at, ended_at, rates) + [ended_at]

      boundaries.each_cons(2).map do |started_at, ended_at|
        Segment.new(started_at:, ended_at:, rate: rate_at(rates, started_at))
      end
    end

    def self.rate_changes_inside(started_at, ended_at, rates)
      rates.map(&:effective_from)
        .select { |at| at > started_at && at < ended_at }
        .uniq
        .sort
    end

    def self.rate_at(rates, timestamp)
      rates.select { |rate| rate.effective_from <= timestamp }.max_by(&:effective_from)
    end

    private_class_method :rate_changes_inside, :rate_at
  end
end
