# frozen_string_literal: true

module Mutations
  module WalletTransactions
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "wallets:top_up"
      # NOTE: Granting or voiding credits and bypassing paid top-up limits go beyond a paid top-up,
      #       so they also need the permission that manages the wallet.
      PRIVILEGED_PERMISSION = "wallets:update"

      graphql_name "CreateCustomerWalletTransaction"
      description "Creates a new Customer Wallet Transaction"

      input_object_class Types::WalletTransactions::CreateInput

      type Types::WalletTransactions::Object.collection_type

      def resolve(**args)
        raise privileged_permission_error if privileged_params?(args) && !context.dig(:permissions, PRIVILEGED_PERMISSION)

        result = ::WalletTransactions::CreateFromParamsService.call(organization: current_organization, params: args)

        result.success? ? result.wallet_transactions : result_error(result)
      end

      private

      # NOTE: The top-up form always sends grantedCredits ("0" when empty) and ignorePaidTopUpLimits,
      #       so only values that actually grant, void or bypass limits are privileged.
      def privileged_params?(args)
        non_zero_amount?(args[:granted_credits]) ||
          non_zero_amount?(args[:voided_credits]) ||
          args[:ignore_paid_top_up_limits] == true
      end

      def non_zero_amount?(value)
        return false if value.nil?

        BigDecimal(value, exception: false) != 0
      end

      def privileged_permission_error
        GraphQL::ExecutionError.new(
          "Missing permissions",
          extensions: {status: :forbidden, code: "forbidden", required_permissions: [PRIVILEGED_PERMISSION]}
        )
      end
    end
  end
end
