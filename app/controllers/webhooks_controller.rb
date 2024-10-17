# frozen_string_literal: true

class WebhooksController < ApplicationController
  def stripe
    result = PaymentProviders::StripeService.new.handle_incoming_webhook(
      organization_id: params[:organization_id],
      code: params[:code].presence,
      params: request.body.read,
      signature: request.headers['HTTP_STRIPE_SIGNATURE']
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
    result = PaymentProviders::Gocardless::HandleIncomingWebhookService.call(
      organization_id: params[:organization_id],
      code: params[:code].presence,
      body: request.body.read,
      signature: request.headers['Webhook-Signature']
    )

    unless result.success?
      if result.error.is_a?(BaseService::ServiceFailure) && result.error.code == 'webhook_error'
        return head(:bad_request)
      end

      result.raise_if_error!
    end

    head(:ok)
  end

  def adyen
    result = PaymentProviders::AdyenService.new.handle_incoming_webhook(
      organization_id: params[:organization_id],
      code: params[:code].presence,
      body: adyen_params.to_h
    )

    unless result.success?
      return head(:bad_request) if result.error.code == 'webhook_error'

      result.raise_if_error!
    end

    render(json: '[accepted]')
  end

  def adyen_params
    params['notificationItems']&.first&.dig('NotificationRequestItem')&.permit!
  end
end
