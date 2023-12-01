# frozen_string_literal: true

module PaymentProviders
  class FindService < BaseService
    attr_reader :code, :organization_id, :scope

    def initialize(organization_id:, code: nil)
      @code = code
      @organization_id = organization_id
      @scope = PaymentProviders::BaseProvider.where(organization_id:)

      super(nil)
    end

    def call
      if code.blank? && scope.count > 1
        return result.service_failure!(
          code: 'payment_provider_code_error',
          message: 'Code is missing',
        )
      end

      @scope = scope.where(code:) if code.present?

      unless scope.exists?
        return result.service_failure!(code: 'payment_provider_not_found', message: 'Payment provider not found')
      end

      result.payment_provider = scope.first
      result
    end
  end
end
