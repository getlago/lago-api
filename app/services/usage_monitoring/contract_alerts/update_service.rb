# frozen_string_literal: true

module UsageMonitoring
  module ContractAlerts
    class UpdateService < BaseService
      include ::UsageMonitoring::Concerns::CreateOrUpdateConcern

      Result = BaseResult[:alert]

      UNCHANGEABLE_FIELDS = %i[code alert_type scope].freeze

      def initialize(alert:, params:)
        @alert = alert
        @params = params.to_h.with_indifferent_access
        super
      end

      def call
        return result.not_found_failure!(resource: "alert") unless alert

        sent = UNCHANGEABLE_FIELDS.select { params.key?(it) }
        return result.validation_failure!(errors: sent.index_with { ["value_cannot_be_changed"] }) if sent.any?

        return result.forbidden_failure!(code: "contract_not_live") unless contracts.live.exists?

        if params.key?(:thresholds)
          thresholds_result = UsageMonitoring::Thresholds::ValidateService.call(thresholds: params[:thresholds])
          return result.fail_with_error!(thresholds_result.error) unless thresholds_result.success?
        end

        alert.with_lock do
          next result.not_found_failure!(resource: "alert") if alert.discarded?

          alert.name = params[:name] if params.key?(:name)
          alert.save!

          if params.key?(:thresholds)
            replace_thresholds(alert, active_contract, keep_previous_notify_on(alert, params[:thresholds]))
          end

          after_commit { UsageMonitoring::TrackContractActivityService.call!(contract: active_contract) } if active_contract
        end
        return result unless result.success?

        result.alert = alert
        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      end

      private

      attr_reader :alert, :params

      def contracts
        alert.organization.contracts.where(external_id: alert.contract_external_id)
      end

      # The only contract evaluated: a pending replacement waits for its activation
      def active_contract
        @active_contract ||= contracts.active.take
      end
    end
  end
end
