# frozen_string_literal: true

module PaymentProviders
  module Webhooks
    module Adyen
      class ChargebackService < BaseService
        def call
          status = event['additionalData']['disputeStatus']
          reason = event['reason']
          provider_payment_id = event['pspReference']

          payment = Payment.find_by(provider_payment_id:)
          return result.not_found_failure!(resource: 'adyen_payment') unless payment

          if status == 'Lost' && event['success'] == 'true'
            return Invoices::LoseDisputeService.call(invoice: payment.invoice, payment_dispute_lost_at:, reason:)
          end

          result
        end

        private

        def event
          @event ||= JSON.parse(event_json)['notificationItems'].first&.dig('NotificationRequestItem')
        end

        def payment_dispute_lost_at
          Time.zone.parse(event['eventDate'])
        end
      end
    end
  end
end
