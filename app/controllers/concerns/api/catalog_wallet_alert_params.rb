# frozen_string_literal: true

module Api
  # The alert fields of a plan wallet's templates and of a contract wallet's alerts
  module CatalogWalletAlertParams
    ALERT_FIELDS = %i[alert_type code name].freeze
    THRESHOLD_FIELDS = %i[code value recurring notify_on].freeze

    private

    # Strong params would drop a list or an object, an item or a field, and save what is left. The fields go through
    # as sent, without unknown ones, so that the service refuses any malformed shape. The update takes the code and
    # the type too, which its service refuses.
    def input_params
      alert_params = params.require(:alert)
      raise ActionController::ParameterMissing, :alert unless alert_params.is_a?(ActionController::Parameters)

      sent = alert_params.to_unsafe_h
      input = sent.slice(*ALERT_FIELDS)
      input[:thresholds] = sent_thresholds(sent[:thresholds]) if sent.key?(:thresholds)
      input
    end

    def sent_thresholds(thresholds)
      return thresholds unless thresholds.is_a?(Array)

      thresholds.map { it.is_a?(Hash) ? it.slice(*THRESHOLD_FIELDS) : it }
    end
  end
end
