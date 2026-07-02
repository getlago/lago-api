# frozen_string_literal: true

module Invoices
  module Search
    class RemoveFromIndexService < BaseService
      Result = BaseResult

      def initialize(invoice_id:)
        @invoice_id = invoice_id
        super
      end

      def call
        return result unless Lago::Meilisearch::Client.enabled?

        Invoice.index.delete_document(invoice_id)
        result
      end

      private

      attr_reader :invoice_id
    end
  end
end
