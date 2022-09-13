# frozen_string_literal: true

module Customers
  class DestroyService < BaseService
    def destroy(id:)
      customer = result.user.customers.find_by(id: id)
      return result.not_found_failure!(resource: 'customer') unless customer
      return result.not_allowed_failure!(code: 'attached_to_an_active_subscription') unless customer.deletable?

      customer.destroy!

      result.customer = customer
      result
    end
  end
end
