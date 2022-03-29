# frozen_string_literal: true

class CustomersService < BaseService
  def create(organization:, params:)
    customer = organization.customers.find_or_initialize_by(customer_id: params[:customer_id])
    customer.name = params[:name]
    customer.save!

    result.customer = customer
    result
  rescue ActiveRecord::RecordInvalid => e
    result.fail_with_validations!(e.record)
  end
end
