# frozen_string_literal: true

module Billing
  module Segments
    Segment = Data.define(:started_at, :ended_at, :rate)

    def self.within(window, rates:)
      segment_starts = [window.begin] + rate_changes_inside(window, rates)

      segment_starts.each_with_index.filter_map do |from, index|
        rate = rate_at(rates, from)
        next unless rate

        Segment.new(started_at: from, ended_at: segment_starts[index + 1] || window.end, rate:)
      end
    end

    def self.rate_changes_inside(window, rates)
      rates.map(&:effective_from)
        .select { |at| at > window.begin && window.cover?(at) }
        .uniq
        .sort
    end

    def self.rate_at(rates, timestamp)
      rates.select { |rate| rate.effective_from <= timestamp }.max_by(&:effective_from)
    end

    private_class_method :rate_changes_inside
  end
end
