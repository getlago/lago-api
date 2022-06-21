# frozen_string_literal: true

module Customers
  class DestroyService < BaseService
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
end
