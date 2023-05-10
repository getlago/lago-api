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

  def adyen
    notification_request_item = params["notificationItems"].first&.dig("NotificationRequestItem")
    signature = notification_request_item.dig("additionalData", "hmacSignature")
    
    result = PaymentProviders::AdyenService.new.handle_incoming_webhook(
      organization_id: params[:organization_id],
      body: notification_request_item,
      signature:
    )
    
    puts notification_request_item["eventCode"]
    puts notification_request_item["merchantReference"]

    unless result.success?
      if result.error.code == 'webhook_error'
        return head(:bad_request)
      end

      result.raise_if_error!
    end

    render json: "[accepted]"
  end
end
