# frozen_string_literal: true

class BackfillInvoiceCustomerSnapshots < ActiveRecord::Migration[8.0]
  def change
    Invoice.where(status: ['finalized', 'voided'])
           .includes(:customer)
           .find_in_batches(batch_size: 1_000) do |batch|
      batch.each do |invoice|
        next if CustomerSnapshot.exists?(invoice_id: invoice.id)

        CustomerSnapshot.create!(
          invoice_id: invoice.id,
          organization_id: invoice.organization_id,
          display_name: invoice.customer.display_name,
          firstname: invoice.customer.firstname,
          lastname: invoice.customer.lastname,
          email: invoice.customer.email,
          phone: invoice.customer.phone,
          url: invoice.customer.url,
          tax_identification_number: invoice.customer.tax_identification_number,
          applicable_timezone: invoice.customer.applicable_timezone,
          address_line1: invoice.customer.address_line1,
          address_line2: invoice.customer.address_line2,
          city: invoice.customer.city,
          state: invoice.customer.state,
          zipcode: invoice.customer.zipcode,
          country: invoice.customer.country,
          legal_name: invoice.customer.legal_name,
          legal_number: invoice.customer.legal_number,
          shipping_address_line1: invoice.customer.shipping_address_line1,
          shipping_address_line2: invoice.customer.shipping_address_line2,
          shipping_city: invoice.customer.shipping_city,
          shipping_state: invoice.customer.shipping_state,
          shipping_zipcode: invoice.customer.shipping_zipcode,
          shipping_country: invoice.customer.shipping_country
        )
      end
    end
  end
end
