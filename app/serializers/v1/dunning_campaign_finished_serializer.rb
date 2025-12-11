# frozen_string_literal: true

module V1
  class DunningCampaignFinishedSerializer < ModelSerializer
    def serialize
      {
        external_customer_id: model.external_id,
        dunning_campaign_code: options[:dunning_campaign_code],
        overdue_balance_cents: model.overdue_balance_cents,
        overdue_balance_currency: model.currency,

        customer_external_id: model.external_id # DEPRECATED
      }
    end
  end
end
