# frozen_string_literal: true

class RefreshStripeWebhooksForDisputes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    PaymentProviders::StripeProvider.find_each do |stripe_provider|
      if stripe_provider.secret_key.present? && stripe_provider.webhook_id.present?
        PaymentProviders::Stripe::RefreshWebhookJob.perform_later(stripe_provider)
      end
    end
  end
end
