# frozen_string_literal: true

module V2
  class ContractTriggeredAlertSerializer < ContractAlertHistorySerializer
    timestamps :triggered_at

    private

    def event_payload
      {crossed_thresholds: model.crossed_thresholds}
    end
  end
end
