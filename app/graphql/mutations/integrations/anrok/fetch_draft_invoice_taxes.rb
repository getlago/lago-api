# frozen_string_literal: true

module Mutations
  module Integrations
    module Anrok
      class FetchDraftInvoiceTaxes < BaseMutation
        include AuthenticableApiUser
        include RequiredOrganization

        REQUIRED_PERMISSION = 'invoices:create'

        description 'Fetches taxes for one-off invoice'

        input_object_class Types::Invoices::CreateInvoiceInput

        type Types::Integrations::AnrokObjects::FeeObject.collection_type

        def resolve(**args)
          customer = Customer.find_by(
            id: args[:customer_id],
            organization_id: current_organization.id
          )

          result = ::Integrations::Aggregator::Taxes::Invoices::CreateDraftService.new(
            invoice: invoice(customer, args),
            fees: fees(args)
          ).call

          result.success? ? result.fees : result_error(result)
        end

        private

        # Note: We need to pass invoice object to the service that return taxes. This service should
        # work with real invoice objects. In this case, it should also work with invoice that is not stored yet,
        # because we need to fetch taxes for one-off invoice UI form.
        def invoice(customer, args)
          OpenStruct.new(
            issuing_date: Time.current.in_time_zone(customer.applicable_timezone).to_date,
            currency: args[:currency],
            customer:
          )
        end

        def fees(args)
          args[:fees].map do |fee|
            unit_amount_cents = fee[:unit_amount_cents]
            units = fee[:units]&.to_f || 1

            OpenStruct.new(
              add_on_id: fee[:add_on_id],
              item_id: fee[:add_on_id],
              sub_total_excluding_taxes_amount_cents: (unit_amount_cents * units).round
            )
          end
        end
      end
    end
  end
end
