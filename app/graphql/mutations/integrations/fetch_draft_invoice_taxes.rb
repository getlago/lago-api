# frozen_string_literal: true

module Mutations
  module Integrations
    class FetchDraftInvoiceTaxes < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "invoices:create"

      description "Fetches taxes for one-off invoice"

      input_object_class Types::Invoices::CreateInvoiceInput

      type Types::Integrations::TaxObjects::FeeObject.collection_type

      def resolve(**args)
        customer = current_organization.customers.find_by(id: args[:customer_id])

        result = ::Integrations::Aggregator::Taxes::Invoices::CreateDraftService.new(
          invoice: invoice(customer, args),
          fees: fees(args)
        ).call

        result.success? ? result.fees : validation_error(messages: {tax_error: [result.error.code]})
      end

      private

      # One-off invoices previewed from the UI are not persisted yet, so we build lightweight
      # stand-ins exposing only the subset of the Invoice / Fee interface the tax payloads read.
      # They fail loudly if a payload starts reading an attribute we did not anticipate.
      DraftInvoice = Data.define(:issuing_date, :currency, :customer) do
        def voided? = false
      end

      DraftFee = Data.define(:add_on_id, :item_id, :sub_total_excluding_taxes_amount_cents) do
        def id = nil

        def item_key = nil

        def units = nil

        def amount_cents = nil

        def charge? = false

        def fixed_charge? = false

        def commitment? = false

        def subscription? = false
      end

      def invoice(customer, args)
        DraftInvoice.new(
          issuing_date: Time.current.in_time_zone(customer.applicable_timezone).to_date,
          currency: args[:currency],
          customer:
        )
      end

      def fees(args)
        args[:fees].map do |fee|
          unit_amount_cents = fee[:unit_amount_cents]
          units = fee[:units]&.to_f || 1

          DraftFee.new(
            add_on_id: fee[:add_on_id],
            item_id: fee[:add_on_id],
            sub_total_excluding_taxes_amount_cents: (unit_amount_cents * units).round
          )
        end
      end
    end
  end
end
