# frozen_string_literal: true

module PaymentProviderCustomers
  class CreateService < BaseService
    def initialize(customer)
      @customer = customer

      super(nil)
    end

    def create(customer_class:, payment_provider_id:, params:)
      provider_customer = customer_class.find_or_initialize_by(
        customer_id: customer.id,
        payment_provider_id: payment_provider_id,
      )
      provider_customer.provider_customer_id = params[:provider_customer_id]
      # TODO: Handle settings and create customer on stripe if no customer id

      provider_customer.save!

      result.provider_customer = provider_customer
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end

    private

    attr_accessor :customer

    delegate :organization, to: :customer
  end
end
