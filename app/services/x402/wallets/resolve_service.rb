# frozen_string_literal: true

module X402
  module Wallets
    class ResolveService < BaseService
      Result = BaseResult[:wallet]

      SHAPE_KEYS = %w[name rate_amount currency paid_top_up_min_amount_cents paid_top_up_max_amount_cents].freeze

      def initialize(customer:, code:, shape:)
        @customer = customer
        @code = code
        @shape = shape

        super
      end

      def call
        result.wallet = find_wallet || create_wallet
        result
      rescue BaseService::FailedResult => e
        result.fail_with_error!(e)
      end

      private

      attr_reader :customer, :code, :shape

      def find_wallet
        customer.wallets.active.find_by(code:)
      end

      def create_wallet
        ActiveRecord::Base.transaction(requires_new: true) do
          ::Wallets::CreateService.call!(
            params: shape.to_h.slice(*SHAPE_KEYS).symbolize_keys.merge(
              organization_id: customer.organization_id,
              customer:,
              code:,
              x402_enabled: true
            )
          ).wallet
        end
      rescue ActiveRecord::RecordNotUnique, BaseService::FailedResult
        find_wallet || raise
      end
    end
  end
end
