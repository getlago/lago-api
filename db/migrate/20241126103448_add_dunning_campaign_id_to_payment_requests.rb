# frozen_string_literal: true

class AddDunningCampaignIdToPaymentRequests < ActiveRecord::Migration[7.1]
  def change
    safety_assured do
      add_reference :payment_requests, :dunning_campaign, type: :uuid, foreign_key: true, index: true
    end
  end
end
