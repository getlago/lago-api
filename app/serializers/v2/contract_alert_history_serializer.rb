# frozen_string_literal: true

module V2
  # A contract alert's history row as its alert.triggered and alert.resolved webhooks send it: the alert and its
  # scope, the contract evaluated and the observed values. Each event adds its own keys and time.
  class ContractAlertHistorySerializer < ModelSerializer
    include ContractAlertScope

    def serialize
      {
        lago_id: model.id,
        lago_alert_id: model.contract_alert_id,
        alert_code: alert.code,
        alert_name: alert.name,
        alert_type: alert.alert_type,
        currency:,
        lago_contract_id: model.contract_id,
        external_contract_id: contract.external_id,
        external_customer_id: contract.customer.external_id,
        current_value: model.current_value,
        previous_value: model.previous_value,
        scope: scope_of(alert),
        **event_payload
      }
    end

    private

    # Alerts are soft-deleted, so the history reads a deleted alert's code and name from the alert itself
    def alert
      model.alert
    end

    def contract
      model.contract
    end

    # Amount values are in cents of the contract's currency; unit values have no currency
    def currency
      contract.currency if alert.alert_type == "usage_amount"
    end
  end
end
