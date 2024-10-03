# frozen_string_literal: true

module PaymentProviders
  class BaseService < BaseService
    private

    def payment_provider_code_changed?(payment_provider, old_code, args)
      payment_provider.persisted? && args.key?(:code) && old_code != args[:code]
    end
  end
end
