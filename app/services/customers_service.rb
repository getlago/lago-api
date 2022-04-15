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

  def destroy(id:)
    customer = result.user.customers.find_by(id: id)
    return result.fail!('not_found') unless customer

    unless customer.deletable?
      return result.fail!(
        'forbidden',
        'Customer is attached to an active subscription',
      )
    end

    customer.destroy!

    result.customer = customer
    result
  end
end
