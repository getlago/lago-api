# frozen_string_literal: true

module PaymentIndex
  extend ActiveSupport::Concern

  def payment_index(customer_external_id: nil)
    filters = params.permit(:invoice_id)
    filters[:external_customer_id] = customer_external_id
    result = PaymentsQuery.call(
      organization: current_organization,
      pagination: {
        page: page_number,
        limit: page_size
      },
      filters: filters
    )

    if result.success?
      render(
        json: ::CollectionSerializer.new(
          result.payments.includes(
            :payment_provider_customer,
            :payment_provider,
            :x402_settlement,
            payable: :customer
          ),
          ::V1::PaymentSerializer,
          collection_name: resource_name.pluralize,
          meta: pagination_metadata(result.payments)
        )
      )
    else
      render_error_response(result)
    end
  end
end
