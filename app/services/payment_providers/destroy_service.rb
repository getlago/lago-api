# frozen_string_literal: true

module PaymentProviders
  class DestroyService < BaseService
    def destroy(id:)
      payment_provider = PaymentProviders::BaseProvider.find_by(
        id: id,
        organization_id: result.user.organization_ids,
      )
      return result.fail!('not_found') unless payment_provider

      payment_provider.destroy!

      result.payment_provider = payment_provider
      result
    end
  end
end
