# frozen_string_literal: true

module UsageMonitoring
  class UpdateAlertService < BaseService
    include ::UsageMonitoring::Concerns::CreateOrUpdateConcern

    Result = BaseResult[:alert]

    def initialize(alert:, params:)
      @alert = alert
      @params = params
      super
    end

    def call
      return result.not_found_failure!(resource: "alert") unless alert

      if params.has_key?(:thresholds) && params[:thresholds].size > AlertThreshold::SOFT_LIMIT
        return result.single_validation_failure!(field: :thresholds, error_code: "too_many_thresholds")
      end

      if thresholds_params.present?
        if duplicate_threshold_values?(thresholds_params)
          return result.single_validation_failure!(field: :thresholds, error_code: "duplicate_threshold_values")
        end

        if !all_threshold_values_present?(thresholds_params)
          return result.single_validation_failure!(field: "thresholds:value", error_code: "value_is_mandatory")
        end

        if !all_threshold_values_numeric?(thresholds_params)
          return result.single_validation_failure!(field: "thresholds:value", error_code: "value_is_invalid")
        end

        if !all_recurring_threshold_values_positive?(thresholds_params)
          return result.single_validation_failure!(field: "thresholds:value", error_code: "recurring_value_is_negative")
        end

        validate_notify_on!(thresholds_params)
        return result unless result.success?
      end

      result.alert = alert

      billable_metric = find_billable_metric_from_params!
      return result unless result.success?

      if params.key?(:code) && wallet_alert_code_taken?(wallet_id: alert.wallet_id, code: params[:code], alert_type: alert.alert_type, excluding_id: alert.id)
        return result.single_validation_failure!(field: :code, error_code: "value_already_exist")
      end

      ActiveRecord::Base.transaction do
        alert.name = params[:name] if params.key?(:name)
        alert.code = params[:code] if params.key?(:code)
        alert.billable_metric = billable_metric if billable_metric
        alert.save!

        if thresholds_params.present?
          alert.thresholds.delete_all
          alert.thresholds.create!(prepare_thresholds(thresholds_params, alert.organization_id))
        end
      end

      track_subscription_activity if alert.subscription_external_id?
      process_wallet_alerts if alert.wallet_id?

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue ActiveRecord::RecordNotUnique => e
      if duplicate_code_error?(e)
        result.single_validation_failure!(field: :code, error_code: "value_already_exist")
      else
        # Only one alert per [alert_type, billable_metric] pair is allowed.
        result.single_validation_failure!(field: :base, error_code: "alert_already_exists")
      end
    end

    private

    attr_reader :alert, :params
    delegate :organization, to: :alert

    def thresholds_params
      return @thresholds_params if defined?(@thresholds_params)

      @thresholds_params = if params[:thresholds].blank?
        params[:thresholds]
      else
        params[:thresholds].map { keep_previous_notify_on(it.to_h.with_indifferent_access) }
      end
    end

    # Thresholds are replaced wholesale, so an update that leaves notify_on out would otherwise
    # revert an opted-in threshold to the column default and silently stop the resolved webhook
    def keep_previous_notify_on(threshold)
      return threshold if threshold.key?(:notify_on)
      return threshold if recurring_param?(threshold)

      previous = previous_notify_on[threshold[:code].to_s]
      return threshold if previous.blank?

      threshold.merge(notify_on: previous)
    end

    def previous_notify_on
      @previous_notify_on ||= alert.thresholds.where.not(code: nil).pluck(:code, :notify_on).to_h
    end

    def track_subscription_activity
      return unless alert.subscription_external_id?
      active_subscription = organization.subscriptions.active
        .find_by(external_id: alert.subscription_external_id)
      return unless active_subscription
      return unless License.premium?

      UsageMonitoring::SubscriptionActivity.insert_all( # rubocop:disable Rails/SkipsModelValidations
        [{organization_id: organization.id, subscription_id: active_subscription.id}],
        unique_by: :idx_subscription_unique
      )
    end

    def process_wallet_alerts
      return unless alert.wallet_id?
      return unless License.premium?
      return unless alert.wallet&.active?

      UsageMonitoring::ProcessWalletAlertsJob.perform_later(alert.wallet)
    end
  end
end
