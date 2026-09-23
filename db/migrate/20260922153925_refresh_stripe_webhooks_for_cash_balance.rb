# frozen_string_literal: true

class RefreshStripeWebhooksForCashBalance < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    PaymentProviders::StripeProvider.find_each do |stripe_provider|
      next if stripe_provider.secret_key.blank?
      next if stripe_provider.webhook_id.blank?

      PaymentProviders::Stripe::RefreshWebhookJob.perform_later(stripe_provider)
    end
  end
end
