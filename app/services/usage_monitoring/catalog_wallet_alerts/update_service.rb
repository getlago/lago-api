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

          # Only the thresholds change: closing an alarm sends alert.resolved, and no payload renders a wallet alert's history
          replace_thresholds(current, nil, keep_previous_notify_on(current, params[:thresholds])) if params.key?(:thresholds)

          result.alert = current
        end

        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      end

      private

      attr_reader :alert, :params
    end
  end
end
