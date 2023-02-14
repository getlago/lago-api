# frozen_string_literal: true

class ChangeWebhooksOrganizationIdToUuid < ActiveRecord::Migration[7.0]
  def change
    remove_column :webhooks, :organization_id, :bigint

    add_reference :webhooks, :organization, type: :uuid, index: true, null: false # rubocop:disable Rails/NotNullColumn
  end
end
