# frozen_string_literal: true

class RefreshStripeWebhooks < ActiveRecord::Migration[7.0]
  def change
    LagoApi::Application.load_tasks
    Rake::Task["stripe:refresh_registered_webhooks"].invoke
  end
end
