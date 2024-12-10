# frozen_string_literal: true

module InvoiceCustomSections
  module Deselect
    class ForAllUsagesService < BaseService
      def initialize(section:)
        @section = section
        super
      end

      def call
        deselect_for_all_usages
        result
      end

      private

      attr_reader :section

      def deselect_for_all_usages
        InvoiceCustomSectionSelection.where(invoice_custom_section_id: section.id).destroy_all
        result.invoice_custom_section = section
      end
    end
  end
end
