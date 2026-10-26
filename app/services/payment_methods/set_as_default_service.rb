# frozen_string_literal: true

module PaymentMethods
  class SetAsDefaultService < BaseService
    Result = BaseResult[:payment_method]

    def initialize(payment_method:, only_when_no_default: false)
      @payment_method = payment_method
      @only_when_no_default = only_when_no_default

      super
    end

    def call
      return result.not_found_failure!(resource: "payment_method") unless payment_method
      if payment_method.is_default?
        result.payment_method = payment_method
        return result
      end

      ActiveRecord::Base.transaction do
        Customers::LockService.call(customer: payment_method.customer, scope: :payment_method) do
          unless skip_default?
            payment_method.customer.payment_methods.where.not(id: payment_method.id).update_all(is_default: false, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
            payment_method.update!(is_default: true)
          end
        end
      end

      result.payment_method = payment_method

      result
    rescue BaseLockService::FailedToAcquireLock => e
      result.lock_acquisition_failure!(message: e.message, error: e)
    end

    private

    attr_reader :payment_method, :only_when_no_default

    def skip_default?
      return false unless only_when_no_default

      payment_method.customer.payment_methods.where(is_default: true).where.not(id: payment_method.id).exists?
    end
  end
end
