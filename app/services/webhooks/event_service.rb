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
        root_name: 'event_error',
      )
    end

    def webhook_type
      'event.error'
    end

    def object_type
      'event_error'
    end
  end
end
