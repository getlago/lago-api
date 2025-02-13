# frozen_string_literal: true

module PaymentProviders
  class StripeService < BaseService
    def create_or_update(**args)
      payment_provider_result = PaymentProviders::FindService.call(
        organization_id: args[:organization_id],
        code: args[:code],
        id: args[:id],
        payment_provider_type: "stripe"
      )

      stripe_provider = if payment_provider_result.success?
        payment_provider_result.payment_provider
      else
        PaymentProviders::StripeProvider.new(
          organization_id: args[:organization_id],
          code: args[:code]
        )
      end

      secret_key = stripe_provider.secret_key
      old_code = stripe_provider.code

      stripe_provider.secret_key = args[:secret_key] if args.key?(:secret_key)
      stripe_provider.code = args[:code] if args.key?(:code)
      stripe_provider.name = args[:name] if args.key?(:name)
      stripe_provider.success_redirect_url = args[:success_redirect_url] if args.key?(:success_redirect_url)
      stripe_provider.save!

      if secret_key != stripe_provider.secret_key
        unregister_webhook(stripe_provider, secret_key)

        PaymentProviders::Stripe::RegisterWebhookJob.perform_later(stripe_provider)
      end

      if payment_provider_code_changed?(stripe_provider, old_code, args)
        stripe_provider.customers.update_all(payment_provider_code: args[:code]) # rubocop:disable Rails/SkipsModelValidations
      end

      result.stripe_provider = stripe_provider
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    def refresh_webhook(stripe_provider:)
      unregister_webhook(stripe_provider, stripe_provider.secret_key)
      PaymentProviders::Stripe::RegisterWebhookService.call(stripe_provider)
    end

    private

    def unregister_webhook(stripe_provider, api_key)
      return if stripe_provider.webhook_id.blank?

      ::Stripe::WebhookEndpoint.delete(
        stripe_provider.webhook_id, {}, {api_key:}
      )
    rescue => e
      # NOTE: Since removing the webbook end-point is not critical
      #       we don't want any error with it to break the update of the
      #       payment provider
      Rails.logger.error(e.message)
      Rails.logger.error(e.backtrace.join("\n"))

      Sentry.capture_exception(e)
    end
  end
end
