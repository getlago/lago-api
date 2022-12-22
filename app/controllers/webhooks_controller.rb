# frozen_string_literal: true

class WebhooksController < ApplicationController
  def stripe
    result = PaymentProviders::StripeService.new.handle_incoming_webhook(
      organization_id: params[:organization_id],
      params: request.body.read,
      signature: request.headers['HTTP_STRIPE_SIGNATURE'],
    )

    unless result.success?
      if result.error.is_a?(BaseService::ServiceFailure) && result.error.code == 'webhook_error'
        return head(:bad_request)
      end

      result.raise_if_error!
    end

    head(:ok)
  end

  def gocardless
    result = PaymentProviders::GocardlessService.new.handle_incoming_webhook(
      organization_id: params[:organization_id],
      body: request.body.read,
      signature: request.headers['Webhook-Signature'],
    )

    unless result.success?
      if result.error.is_a?(BaseService::ServiceFailure) && result.error.code == 'webhook_error'
        return head(:bad_request)
      end

      result.raise_if_error!
    end

    head(:ok)
  end
end
