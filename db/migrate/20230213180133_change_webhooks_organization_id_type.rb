# frozen_string_literal: true

class ChangeWebhooksOrganizationIdType < ActiveRecord::Migration[7.0]
  def change
    remove_column :webhooks, :organization_id

    add_reference :webhooks, :organization, index: true, type: :uuid
  end
end
