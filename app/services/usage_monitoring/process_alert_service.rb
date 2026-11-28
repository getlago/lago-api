# frozen_string_literal: true

module UsageMonitoring
  class ProcessAlertService < BaseService
    Result = BaseResult[:alert]

    def initialize(alert:, current_metrics:, alertable:, expected_billable_metric_id: nil, measured_at: nil)
      @alert = alert
      @alertable = alertable
      @current_metrics = current_metrics
      @expected_billable_metric_id = expected_billable_metric_id
      @measured_at = measured_at
      super
    end

    def call
      now = Time.current

      alert.with_lock do
        # NOTE: the lock reloads the alert past its default scope, so an alert deleted since the caller loaded it shows up here
        next if alert.discarded?

        # NOTE: the caller measured usage for one metric, so a metric changed since then makes that usage
        # unrelated to the configuration now held under the lock
        next if stale_metric?

        # NOTE: two evaluations of one alert can finish out of order: an older usage would overwrite previous_value
        next if stale_usage?

        # NOTE: a wallet loaded before the lock (or evaluated concurrently by the job and the wallet alerts consumer) can
        # hold an older balance: reading it under the lock keeps it from overwriting previous_value and triggering twice
        current_metrics.reload if alert.watches_wallet?
        # NOTE: read inside the lock so the metric selection and the thresholds come from the same configuration
        current = alert.find_value(current_metrics)

        # NOTE: current is nil if the alert is set for a billable metric which is not part of any charges of the plan
        evaluate(current, now) unless current.nil?

        alert.last_processed_at = processed_at(now)
        alert.save!
      end

      result.alert = alert
      result
    end

    private

    attr_reader :alert, :alertable, :current_metrics, :expected_billable_metric_id, :measured_at

    def stale_metric?
      expected_billable_metric_id.present? && alert.billable_metric_id != expected_billable_metric_id
    end

    def stale_usage?
      measured_at.present? && alert.last_processed_at.present? && alert.last_processed_at > measured_at
    end

    def evaluate(current, now)
      # The cards of a contract rebaseline one by one. Its types never roll over as a whole (period_rolled_over?),
      # so resolution still runs, on the cards still in their window: a renewal alone resolves nothing.
      if alert.is_a?(ContractAlert)
        windows = alert.windows_in_scope(current_metrics)
        rebaseline_renewed_windows(windows)
      end

      # Re-baselining discards the evidence a recovery would be measured against, so it replaces the resolution.
      rebaselined = period_rolled_over? && alert.window_resets_each_period?(alertable)
      alert.previous_value = 0 if rebaselined

      crossed_threshold_values = alert.find_thresholds_crossed(current)

      if crossed_threshold_values.present?
        record_trigger(crossed_threshold_values, current, now)
      elsif !rebaselined
        record_resolution(current, now)
      end

      alert.previous_value = current
      alert.previous_windows = windows.reject { |_, window| BigDecimal(window["value"]).zero? } if windows
    end

    # The cards of a contract renew on their own dates, so the baseline keeps only the value of the cards still
    # measuring the window of the last evaluation. Summing them rather than subtracting the others from
    # previous_value, which is rounded to its column, takes a single card back to exactly 0.
    def rebaseline_renewed_windows(windows)
      kept = alert.previous_windows.select { |slice, _| alert.same_window?(slice, windows[slice]) }

      if kept.size < alert.previous_windows.size
        alert.previous_value = kept.values.sum(BigDecimal(0)) { BigDecimal(it["value"]) }
      end
    end

    def period_rolled_over?
      return false unless Alert::CURRENT_USAGE_TYPES.include?(alert.alert_type)
      return false if alert.last_processed_at.nil?

      # NOTE: from_datetime arrives as an ISO8601 string on the usage path, hence the parse
      alert.last_processed_at < Time.zone.parse(current_metrics.from_datetime.to_s)
    end

    # NOTE: usage measured just before a renewal but processed after it still belongs to the old period. Stamping it
    # with the clock time would place it in the new period, and the first evaluation there would miss the rollover.
    # The measurement time, when given, is what stale_usage? compares the next usage with. It is read just before
    # the usage picks its period, so it can fall before a period that just opened: kept at its start for the rollover.
    def processed_at(now)
      time = measured_at || now
      return time unless Alert::CURRENT_USAGE_TYPES.include?(alert.alert_type)

      time = [time, Time.zone.parse(current_metrics.from_datetime.to_s)].max if measured_at && current_metrics.from_datetime.present?
      return time if current_metrics.to_datetime.blank?

      [time, Time.zone.parse(current_metrics.to_datetime.to_s)].min
    end

    def record_trigger(crossed_threshold_values, current, now)
      triggered_alert = alert.all_triggered_alerts.create!(
        organization: alert.organization,
        alertable:,
        current_value: current,
        previous_value: alert.previous_value,
        crossed_thresholds: alert.formatted_crossed_thresholds(crossed_threshold_values),
        triggered_at: now
      )

      after_commit { SendWebhookJob.perform_later("alert.triggered", triggered_alert) }
    end

    def record_resolution(current, now)
      recovered_values = alert.find_thresholds_recovered(current)
      return if recovered_values.empty?

      recorded = alert.recorded_alarm_codes
      announced = alert.opted_in_thresholds.filter { recovered_values.include?(it.value) && recorded.include?(it.code) }
      return if announced.empty?

      resolved_alert = alert.all_triggered_alerts.create!(
        organization: alert.organization,
        alertable:,
        kind: :resolved,
        resolution_reason: :recovered,
        current_value: current,
        previous_value: alert.previous_value,
        crossed_thresholds: alert.formatted_crossed_thresholds(announced.map(&:value)),
        in_alarm_thresholds: alert.in_alarm_line_labels(current),
        fully_resolved: alert.fully_resolved?(current),
        triggered_at: now
      )

      SendWebhookJob.perform_after_commit("alert.resolved", resolved_alert)
    end
  end
end
