# frozen_string_literal: true

module V2
  # A catalog wallet alert's history row as its alert.triggered and alert.resolved webhooks send it: the alert, its
  # wallet and the observed values, in the wallet currency's cents. Each event adds its own keys and time.
  class CatalogWalletAlertHistorySerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        lago_alert_id: model.catalog_wallet_alert_id,
        alert_code: model.alert_code,
        alert_name:,
        alert_type: model.alert_type,
        lago_wallet_id: wallet.id,
        wallet_code: wallet.code,
        currency: wallet.currency,
        lago_contract_id: wallet.contract_id,
        external_contract_id: wallet.contract.external_id,
        contract_code: wallet.contract.code,
        external_customer_id: wallet.customer.external_id,
        current_value: model.current_value,
        previous_value: model.previous_value,
        **event_payload
      }
    end

    private

    def wallet
      model.catalog_wallet
    end

    # Alerts are deleted for good: once the alert is gone, its history keeps the name it had
    def alert_name
      model.alert ? model.alert.name : model.alert_name
    end
  end
end
