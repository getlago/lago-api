# frozen_string_literal: true

module Webhooks
    module Invoices
      class InvoicePaymentSuccessService < Webhooks::BaseService
        private
  
        def current_organization
          @current_organization ||= object.organization
        end
  
        def object_serializer
            ::V1::InvoiceSerializer.new(
              object,
              root_name: 'invoice',
            )
          end
  
        def webhook_type
          'invoice.payment_success'
        end
  
        def object_type
            'invoice'
        end
      end
    end
  end
  