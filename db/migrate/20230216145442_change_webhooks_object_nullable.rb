# frozen_string_literal: true

class ChangeWebhooksObjectNullable < ActiveRecord::Migration[7.0]
  def change
    change_column_null :webhooks, :object_id, true # rubocop:disable Rails/BulkChangeTable
    change_column_null :webhooks, :object_type, true # rubocop:disable Rails/BulkChangeTable
  end
end
