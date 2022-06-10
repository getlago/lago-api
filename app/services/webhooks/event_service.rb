# frozen_string_literal: true

module Webhooks
  class EventService < Webhooks::BaseService
    private

    def current_organization
      @current_organization ||= Organization.find(object[:organization_id])
    end

    def object_serializer
      ::ErrorSerializer.new(
        OpenStruct.new(object),
        root_name: 'error_event',
      )
    end

    def webhook_type
      'event.error'
    end

    def object_type
      'error'
    end
  end
end
