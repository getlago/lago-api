# frozen_string_literal: true

class WebhooksController < ApplicationController
  def stripe
    result = PaymentProviders::StripeService.new.handle_incoming_webhook(
      organization_id: params[:organization_id],
      params: request.body.read,
      signature: request.headers['HTTP_STRIPE_SIGNATURE'],
    )

    unless result.success?
      return head(:bad_request) if result.error_code == 'webhook_error'

      result.throw_error
    end

    head(:ok)
  end
end
