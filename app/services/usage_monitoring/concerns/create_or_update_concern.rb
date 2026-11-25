# frozen_string_literal: true

module UsageMonitoring
  module Concerns
    module CreateOrUpdateConcern
      extend ActiveSupport::Concern

      CODE_UNIQUE_INDEXES = %w[
        idx_alerts_code_unique_per_subscription
        idx_alerts_code_unique_per_wallet
      ].freeze

      def duplicate_code_error?(exception)
        CODE_UNIQUE_INDEXES.any? { |index| exception.message.include?(index) }
      end

      def find_billable_metric_from_params!
        if params[:billable_metric]
          params[:billable_metric]
        elsif params[:billable_metric_id]
          organization.billable_metrics.find_by!(id: params[:billable_metric_id])
        elsif params[:billable_metric_code]
          organization.billable_metrics.find_by!(code: params[:billable_metric_code])
        end
      rescue ActiveRecord::RecordNotFound
        result.not_found_failure!(resource: "billable_metric")
      end

      def wallet_alert_type_taken?(wallet_id:, alert_type:)
        return false if wallet_id.blank?

        organization.alerts.where(wallet_id:, alert_type:).exists?
      end

      def wallet_alert_code_taken?(wallet_id:, code:, excluding_id: nil)
        return false if wallet_id.blank? || code.blank?

        scope = organization.alerts.where(wallet_id:, code:)
        scope = scope.where.not(id: excluding_id) if excluding_id
        scope.exists?
      end

      # `still_in_alarm_at:` keeps only the lines also in alarm at that value
      def seed_alarms_already_past(alert, alertable, still_in_alarm_at: nil)
        return if alertable.nil?

        in_alarm = alert.thresholds_in_alarm(alert.previous_value)
        in_alarm = in_alarm.select { alert.in_alarm?(it.value, still_in_alarm_at) } unless still_in_alarm_at.nil?
        return if in_alarm.empty?

        recorded = alert.recorded_alarm_codes
        already_past = in_alarm.reject { recorded.include?(it.code) }
        return if already_past.empty?

        alert.all_triggered_alerts.create!(
          organization: alert.organization,
          alertable:,
          kind: :seeded,
          current_value: alert.previous_value,
          previous_value: alert.previous_value,
          crossed_thresholds: alert.formatted_crossed_thresholds(already_past.map(&:value)),
          triggered_at: Time.current
        )
      end

      # Callers pass validated thresholds and hold the alert's lock: the current thresholds are deleted before the new ones exist.
      # Without an alertable there is no observed value to seed or resolve against: only the thresholds change.
      def replace_thresholds(alert, alertable, thresholds)
        lines_before = alertable ? announced_lines_in_alarm(alert) : []
        alert.thresholds.delete_all
        alert.thresholds.create!(prepare_thresholds(thresholds, alert.organization_id))
        alert.reload_thresholds
        seed_after_edit(alert, alertable)
        resolve_alarms_closed_by_edit(alert, alertable, lines_before)
      end

      # An alert family that seeds an edit differently overrides this step only
      def seed_after_edit(alert, alertable)
        seed_alarms_already_past(alert, alertable)
      end

      # Thresholds are replaced wholesale, so an update that leaves notify_on out would otherwise
      # revert an opted-in threshold to the column default and silently stop the resolved webhook
      def keep_previous_notify_on(alert, thresholds)
        previous_notify_on = alert.thresholds.where.not(code: nil).pluck(:code, :notify_on).to_h
        incoming_codes = thresholds.map { it.to_h.with_indifferent_access[:code].to_s }

        thresholds.map { with_previous_notify_on(it.to_h.with_indifferent_access, previous_notify_on, incoming_codes) }
      end

      def with_previous_notify_on(threshold, previous_notify_on, incoming_codes)
        return threshold if threshold.key?(:notify_on)
        return threshold if recurring_param?(threshold)
        # A code sent twice cannot tell which threshold the stored opt-in belongs to
        return threshold if incoming_codes.count(threshold[:code].to_s) > 1

        previous = previous_notify_on[threshold[:code].to_s]
        previous.blank? ? threshold : threshold.merge(notify_on: previous)
      end

      # The opted-in lines in alarm before an edit, as they were announced, so their alarm can be closed afterwards.
      def announced_lines_in_alarm(alert)
        alert.thresholds_in_alarm(alert.previous_value).map { {code: it.code, value: it.value, recurring: false} }
      end

      # An edit can take a line out of alarm without any change in usage. Nothing would ever evaluate it as a
      # recovery, so the alarm the customer was told about is closed here, with the reason it closed.
      def resolve_alarms_closed_by_edit(alert, alertable, lines_before)
        return if alertable.nil? || lines_before.empty?

        recorded = alert.recorded_alarm_codes
        still_in_alarm = alert.thresholds_in_alarm(alert.previous_value).map(&:code)
        opted_in_codes = alert.opted_in_thresholds.map(&:code)
        present_codes = alert.thresholds.filter_map { it.code.presence }

        closed = lines_before.select { recorded.include?(it[:code]) && still_in_alarm.exclude?(it[:code]) }
        removed, kept = closed.partition { present_codes.exclude?(it[:code]) }
        # A line still present but opted out of resolutions is not announced.
        updated = kept.select { opted_in_codes.include?(it[:code]) }

        {threshold_updated: updated, threshold_removed: removed}.each do |reason, lines|
          next if lines.empty?

          resolved_alert = alert.all_triggered_alerts.create!(
            organization: alert.organization,
            alertable:,
            kind: :resolved,
            resolution_reason: reason,
            current_value: alert.previous_value,
            previous_value: alert.previous_value,
            crossed_thresholds: lines,
            in_alarm_thresholds: alert.in_alarm_line_labels(alert.previous_value),
            fully_resolved: alert.fully_resolved?(alert.previous_value),
            triggered_at: Time.current
          )
          SendWebhookJob.perform_after_commit("alert.resolved", resolved_alert)
        end
      end

      def duplicate_threshold_values?(thresholds)
        threshold_keys = thresholds.map { |t| [t[:value], recurring_param?(t)] }
        threshold_keys.size != threshold_keys.uniq.size
      end

      def recurring_param?(threshold)
        ActiveModel::Type::Boolean.new.cast(threshold[:recurring]) || false
      end

      def all_threshold_values_present?(thresholds)
        thresholds.none? { it[:value].nil? }
      end

      def all_threshold_values_numeric?(thresholds)
        thresholds.all? { |t| valid_numeric_value?(t[:value]) }
      end

      # v1 reports a notify_on error on the list as a whole
      def validate_notify_on!(thresholds)
        _index, field, error_code = notify_on_violation(thresholds)

        if error_code == "duplicate_threshold_codes"
          result.single_validation_failure!(field: :thresholds, error_code:)
        elsif error_code
          result.single_validation_failure!(field: "thresholds:#{field}", error_code:)
        end
      end

      # The first threshold that breaks a notify_on rule, as [index, field, error_code], or nil
      def notify_on_violation(thresholds)
        if (index = thresholds.index { !valid_notify_on?(it) })
          return [index, :notify_on, "value_is_invalid"]
        end

        if (index = thresholds.index { notify_on_for(it).exclude?(AlertThreshold::NOTIFY_ON_TRIGGERED) })
          return [index, :notify_on, "triggered_is_mandatory"]
        end

        opting_in = thresholds.each_index.select { notify_on_for(thresholds[it]).include?(AlertThreshold::NOTIFY_ON_RESOLVED) }

        if (index = opting_in.find { recurring_param?(thresholds[it]) })
          return [index, :notify_on, "recurring_not_supported"]
        end

        if (index = opting_in.find { thresholds[it][:code].blank? })
          return [index, :code, "value_is_mandatory"]
        end

        opted_in_codes = opting_in.map { thresholds[it][:code] }
        index = later_duplicate_index(thresholds.map { it[:code].presence }) { opted_in_codes.include?(it) }
        [index, :code, "duplicate_threshold_codes"] if index
      end

      def valid_notify_on?(threshold)
        # A plain value such as "resolved" would otherwise read as a one-item list and hide a malformed request
        return false unless threshold[:notify_on].nil? || threshold[:notify_on].is_a?(Array)

        notify_on_for(threshold).all? { AlertThreshold::NOTIFY_ON_VALUES.include?(it) }
      end

      # The later of two equal items, so the first one stays valid in the client's form
      def later_duplicate_index(items)
        items.each_index.find do |index|
          item = items[index]
          !item.nil? && items.first(index).include?(item) && (!block_given? || yield(item))
        end
      end

      def all_recurring_threshold_values_positive?(thresholds)
        thresholds.all? do |t|
          value = ActiveModel::Type::Decimal.new.cast(t[:value])

          !recurring_param?(t) || value.positive?
        end
      end

      def notify_on_for(threshold)
        values = threshold[:notify_on]
        return [AlertThreshold::NOTIFY_ON_TRIGGERED] if values.nil?

        Array(values).map(&:to_s)
      end

      def valid_numeric_value?(value)
        case value
        when Numeric
          true
        when String
          return false if value.blank?

          Float(value)
          true
        else
          false
        end
      rescue ArgumentError
        false
      end
    end
  end
end
