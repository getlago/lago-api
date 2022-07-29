# frozen_string_literal: true

module Webhooks
  class InvoicesService < Webhooks::BaseService
    private

    def current_organization
      @current_organization ||= object.organization
    end

    def object_serializer
      ::V1::InvoiceSerializer.new(
        object,
        root_name: 'invoice',
        includes: %i[customer subscriptions fees credits],
      )
    end

    def webhook_type
      'invoice.created'
    end

    def object_type
      'invoice'
    end
  end
end
