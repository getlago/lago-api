# frozen_string_literal: true

module UsageMonitoring
  module ThresholdEvaluation
    extend ActiveSupport::Concern

    # `previous:` lets a caller cross from another value without changing the stored previous_value
    def find_thresholds_crossed(current, previous: previous_value)
      if increasing?
        find_thresholds_crossed_increasing(current, previous:)
      else
        find_thresholds_crossed_decreasing(current, previous:)
      end
    end

    def find_thresholds_crossed_increasing(current, previous: previous_value)
      crossed = []
      return crossed if current <= previous

      if one_time_thresholds_values.present?
        return crossed if current < one_time_thresholds_values.first

        if previous < one_time_thresholds_values.last
          crossed += one_time_thresholds_values.filter { it > previous && it <= current }
        end
      end

      crossed += find_recurring_thresholds_crossed_increasing(
        previous, current, recurring_threshold&.value, one_time_thresholds_values.last || 0
      )

      crossed.uniq.sort
    end

    def find_thresholds_crossed_decreasing(current, previous: previous_value)
      crossed = []
      return crossed if current >= previous

      if one_time_thresholds_values.present?
        return crossed if current > one_time_thresholds_values.last

        if previous > one_time_thresholds_values.first
          crossed += one_time_thresholds_values.filter { it < previous && it >= current }
        end
      end

      crossed += find_recurring_thresholds_crossed_decreasing(
        previous, current, recurring_threshold&.value, one_time_thresholds_values.first || 0
      )

      crossed.uniq.sort
    end

    def find_thresholds_recovered(current)
      one_time_thresholds_values.filter { in_alarm?(it, previous_value) && !in_alarm?(it, current) }
    end

    def in_alarm?(threshold_value, observed_value)
      if increasing?
        threshold_value <= observed_value
      else
        threshold_value >= observed_value
      end
    end

    def opted_in_thresholds
      thresholds.filter { !it.recurring && it.notify_on_resolved? && it.code.present? }
    end

    def thresholds_in_alarm(observed_value)
      opted_in_thresholds.filter { in_alarm?(it.value, observed_value) }
    end

    # Every line still in alarm, opted in or not, named by its code or by its value when it has no code,
    # so the list covers the same lines as fully_resolved?
    def in_alarm_line_labels(observed_value)
      alarm_lines.filter { in_alarm?(it, observed_value) }.map { line_label(it) }
    end

    def fully_resolved?(observed_value)
      alarm_lines.none? { in_alarm?(it, observed_value) }
    end

    # A recurring threshold holds a step, not a line: its first line sits one step past the last one-time threshold.
    def alarm_lines
      return one_time_thresholds_values unless recurring_threshold

      step = recurring_threshold.value
      if increasing?
        one_time_thresholds_values + [(one_time_thresholds_values.last || 0) + step]
      else
        one_time_thresholds_values + [(one_time_thresholds_values.first || 0) - step]
      end
    end

    # Pairing is by code across the whole history. That is enough: a line only gets back into alarm through
    # a crossing, which records a new triggered row, or through seeding, which records a seeded one.
    def recorded_alarm_codes
      all_triggered_alerts
        .where(kind: [:triggered, :seeded])
        .pluck(:crossed_thresholds)
        .flatten
        .filter_map { it["code"].presence }
        .to_set
    end

    def recurring_threshold
      @recurring_threshold ||= thresholds.find { |th| th.recurring }
    end

    # Thresholds are replaced wholesale on update: drop what was read from the previous set.
    def reload_thresholds
      thresholds.reset
      @recurring_threshold = nil
      @one_time_thresholds_values = nil
    end

    def one_time_thresholds_values
      @one_time_thresholds_values ||= thresholds.filter_map { |th| th.value unless th.recurring }.uniq.sort
    end

    def formatted_crossed_thresholds(crossed_threshold_values)
      regular_thresholds_values, recurring_thresholds_values = crossed_threshold_values.partition do |v|
        one_time_thresholds_values.include?(v)
      end

      formatted_regular_thresholds = thresholds
        .reject { it.recurring }
        .filter { regular_thresholds_values.include?(it.value) }
        .map { |t| {code: t.code, value: t.value, recurring: false} }

      formatted_recurring_thresholds = recurring_thresholds_values
        .map { |v| {code: recurring_threshold&.code, value: v, recurring: true} }

      formatted_regular_thresholds + formatted_recurring_thresholds
    end

    private

    def line_label(line_value)
      threshold = if one_time_thresholds_values.include?(line_value)
        thresholds.find { !it.recurring && it.value == line_value }
      else
        recurring_threshold
      end

      threshold&.code.presence || line_value.to_s("F")
    end

    def find_recurring_thresholds_crossed_increasing(previous, current, step, initial)
      return [] unless step

      # The recurring threshold equal to `previous` was already crossed, so the first one to cross is strictly above it
      first_step = [((previous - initial) / step).floor + 1, 1].max
      first_threshold = initial + first_step * step

      last_step = ((current - initial) / step).floor
      last_threshold = initial + last_step * step

      return [] if first_threshold > last_threshold

      (first_threshold..last_threshold).step(step).to_a
    end

    def find_recurring_thresholds_crossed_decreasing(previous, current, step, initial)
      return [] unless step

      # The recurring threshold equal to `previous` was already crossed, so the first one to cross is strictly below it
      first_step = [((initial - previous) / step).floor + 1, 1].max
      first_threshold = initial - first_step * step

      last_step = ((initial - current) / step).floor
      last_threshold = initial - last_step * step

      return [] if first_threshold < last_threshold

      last_threshold.step(first_threshold, step).to_a
    end
  end
end
