# frozen_string_literal: true

module Billing
  module Segments
    Segment = Data.define(:started_at, :ended_at, :rate)

    # Split the half-open window at each rate change, keeping unpriced periods with rate: nil.
    def self.within(window, rates:)
      boundaries = [window.started_at] + rate_changes_inside(window, rates) + [window.ended_at]

      boundaries.each_cons(2).map do |started_at, ended_at|
        Segment.new(started_at:, ended_at:, rate: rate_at(rates, started_at))
      end
    end

    def self.rate_changes_inside(window, rates)
      rates.map(&:effective_from)
        .select { |at| at > window.started_at && at < window.ended_at }
        .uniq
        .sort
    end

    def self.rate_at(rates, timestamp)
      rates.select { |rate| rate.effective_from <= timestamp }.max_by(&:effective_from)
    end

    private_class_method :rate_changes_inside, :rate_at
  end
end
