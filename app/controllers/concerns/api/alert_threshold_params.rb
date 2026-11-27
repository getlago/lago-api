# frozen_string_literal: true

module Api
  # Strong params would drop a threshold that is not an object and shift the indexes of the ones after it, which the
  # errors name. The items go through as sent, without unknown fields. Rails still drops null items when it parses the body.
  module AlertThresholdParams
    THRESHOLD_FIELDS = %i[code value recurring notify_on].freeze

    private

    def sent_thresholds(thresholds)
      return thresholds unless thresholds.is_a?(Array)

      thresholds.map { it.is_a?(Hash) ? it.slice(*THRESHOLD_FIELDS) : it }
    end
  end
end
