# frozen_string_literal: true

class ChangeWebhooksOrganizationIdToUuid < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      remove_column :webhooks, :organization_id, :bigint

      add_reference :webhooks, :organization, type: :uuid, index: true, null: false # rubocop:disable Rails/NotNullColumn
    end
  end
end
