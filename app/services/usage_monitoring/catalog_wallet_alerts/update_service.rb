# frozen_string_literal: true

module UsageMonitoring
  module CatalogWalletAlerts
    class UpdateService < BaseService
      include ::UsageMonitoring::Concerns::CreateOrUpdateConcern

      Result = BaseResult[:alert]

      UNCHANGEABLE_FIELDS = %i[code alert_type].freeze

      def initialize(alert:, params:)
        @alert = alert
        @params = params.to_h.with_indifferent_access
        super
      end

      def call
        return result.not_found_failure!(resource: "alert") unless alert

        sent = UNCHANGEABLE_FIELDS.select { params.key?(it) }
        return result.validation_failure!(errors: sent.index_with { ["value_cannot_be_changed"] }) if sent.any?

        validate_single_values(params, %i[name])
        return result unless result.success?

        if params.key?(:thresholds)
          validate_thresholds(params[:thresholds], alert.alert_type)
          return result unless result.success?
        end

        ActiveRecord::Base.transaction do
          lock_wallet(wallet_of(alert))
          return result unless result.success?

          # Read again under the lock: a write that held it may have changed the alert or deleted it
          current = alert.class.lock.find_by(id: alert.id)
          return result.not_found_failure!(resource: "alert") unless current

          current.name = params[:name] if params.key?(:name)
          # The thresholds are part of the alert's body, so replacing them dates it too
          current.updated_at = Time.current if params.key?(:thresholds)
          current.save!

          if params.key?(:thresholds)
            thresholds = keep_previous_notify_on(current, params[:thresholds])
            if watching?(current)
              replace_watched_thresholds(current, thresholds)
            else
              replace_thresholds(current, nil, thresholds)
            end
          end

          result.alert = current
        end

        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      end

      private

      attr_reader :alert, :params

      def watching?(alert)
        alert.is_a?(CatalogWalletAlert) && !alert.previous_value.nil?
      end

      # The v1 edit of an alert with a baseline, seeding as below: an alarm the edit closes sends alert.resolved, with
      # threshold_updated or threshold_removed
      def replace_watched_thresholds(alert, thresholds)
        lines_before = announced_lines_in_alarm(alert)
        replace_thresholds(alert, nil, thresholds)
        seed_lines_in_alarm(alert)
        resolve_alarms_closed_by_edit(alert, alert.catalog_wallet, lines_before)
      end

      # Seeds what a create would seed now, the opted-in lines in alarm at the value of a wallet holding money, less
      # those the next evaluation crosses or recovers: it keeps the lines in alarm at the stored value too
      def seed_lines_in_alarm(alert)
        wallet = alert.catalog_wallet
        seed_alarms_already_past(alert, wallet, still_in_alarm_at: alert.find_value(wallet)) if wallet.funded?
      end
    end
  end
end
