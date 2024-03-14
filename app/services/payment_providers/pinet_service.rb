# frozen_string_literal: true

module PaymentProviders
  class PinetService < BaseService
    def create_or_update(**args)
      unless auth_token_valid?(args)
        # TODO define a code for this error
        return result.service_failure!(code: 'auth_token_error', message: 'Invalid token')
      end

      pinet_provider = find_or_initialize_provider(args[:organization_id])
      update_provider_keys(pinet_provider, args[:private_key], args[:key_id])

      result.pinet_provider = pinet_provider
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    def auth_token_valid?(args)
      auth_token = Pinet::JwtService.create_jwt(private_key: args[:private_key], key_id: args[:key_id])
      Pinet::Client.new.valid_auth_token?(auth_token)
    rescue OpenSSL::PKey::RSAError
      false
    end

    def find_or_initialize_provider(organization_id)
      PaymentProviders::PinetProvider.find_or_initialize_by(organization_id:)
    end

    def update_provider_keys(pinet_provider, private_key, key_id)
      old_key_id = pinet_provider.key_id
      old_private_key = pinet_provider.private_key

      pinet_provider.update!(key_id:, private_key:)

      return unless old_key_id != key_id || old_private_key != private_key

      reattach_provider_customers(pinet_provider)
    end

    def reattach_provider_customers(pinet_provider)
      PaymentProviderCustomers::PinetCustomer
        .joins(:customer)
        .where(payment_provider_id: nil, customers: { organization_id: pinet_provider.organization_id })
        .update_all(payment_provider_id: pinet_provider.id)
    end
  end
end
