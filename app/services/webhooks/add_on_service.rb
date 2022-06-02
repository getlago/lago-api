# frozen_string_literal: true

module Webhooks
  class AddOnService < Webhooks::BaseService
    private

    def current_organization
      @current_organization ||= object.organization
    end

    def object_serializer
      ::V1::InvoiceSerializer.new(
        object,
        root_name: 'invoice',
        includes: %i[customer subscription fees],
      )
    end

    def webhook_type
      'invoice.add_on_added'
    end
  end
end
