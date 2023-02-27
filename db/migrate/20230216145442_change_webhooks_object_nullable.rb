# frozen_string_literal: true

class ChangeWebhooksObjectNullable < ActiveRecord::Migration[7.0]
  def change
    change_column_null :webhooks, :object_id, true
    change_column_null :webhooks, :object_type, true
  end
end
