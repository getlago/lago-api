# frozen_string_literal: true

module Mutations
  module InvoiceCustomSections
    class Update < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = 'invoice_custom_sections:update'

      graphql_name 'UpdateInvoiceCustomSection'
      description 'Updates an InvoiceCustomSection'

      input_object_class Types::InvoiceCustomSections::UpdateInput

      type Types::InvoiceCustomSections::Object

      def resolve(**args)
        selected = args.delete(:selected) || false
        invoice_custom_section = ::InvoiceCustomSection.find(args.delete(:id))
        result = ::InvoiceCustomSections::UpdateService.call(
          invoice_custom_section:, update_params: args.to_h, selected: selected
        )

        result.success? ? result.invoice_custom_section : result_error(result)
      end
    end
  end
end
