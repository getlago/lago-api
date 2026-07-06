# frozen_string_literal: true

module Invoices
  module Search
    class IndexService < BaseService
      Result = BaseResult

      def initialize(invoice:)
        @invoice = invoice
        super
      end

      def call
        return result unless Lago::Meilisearch.indexing_enabled?

        invoice.ms_index!
        result
      end

      private

      attr_reader :invoice
    end
  end
end
