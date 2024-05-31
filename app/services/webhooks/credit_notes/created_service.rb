# frozen_string_literal: true

module Webhooks
  module CreditNotes
    class CreatedService < Webhooks::BaseService
      def current_organization
        @current_organization ||= object.organization
      end

      def object_serializer
        ::V1::CreditNoteSerializer.new(
          object,
          root_name: 'credit_note',
          includes: %i[customer items applied_taxes]
        )
      end

      def webhook_type
        'credit_note.created'
      end

      def object_type
        'credit_note'
      end
    end
  end
end
