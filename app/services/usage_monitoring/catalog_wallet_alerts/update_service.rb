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

        # Template writes lock the plan wallet, so a contract copying its templates sees one version of them
        alert.plan_wallet.with_lock do
          return result.not_found_failure!(resource: "plan_wallet") if alert.plan_wallet.discarded?

          # Read again under the lock: a write that held it may have changed the template or deleted it
          template = PlanWalletAlert.find_by(id: alert.id)
          return result.not_found_failure!(resource: "alert") unless template

          template.name = params[:name] if params.key?(:name)
          # The thresholds are part of the template's body, so replacing them dates it too
          template.updated_at = Time.current if params.key?(:thresholds)
          template.save!

          # A template has no observed value, so only the thresholds change
          replace_thresholds(template, nil, keep_previous_notify_on(template, params[:thresholds])) if params.key?(:thresholds)

          result.alert = template
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
