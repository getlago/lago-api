# frozen_string_literal: true

module Mutations
  module Wallets
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "wallets:create"
      # NOTE: Granting credits, bypassing paid top-up limits and managing recurring rules
      #       go beyond creating a wallet, so they also need the permission that manages the wallet.
      PRIVILEGED_PERMISSION = "wallets:update"

      graphql_name "CreateCustomerWallet"
      description "Creates a new Customer Wallet"

      input_object_class Types::Wallets::CreateInput

      type Types::Wallets::Object

      def resolve(**args)
        raise not_enough_permissions_error(PRIVILEGED_PERMISSION) if privileged_params?(args) && !context.dig(:permissions, PRIVILEGED_PERMISSION)

        if args[:payment_term]
          args[:payment_term] = args[:payment_term].to_h
        end

        result = ::Wallets::CreateService.call(
          params: args.merge(organization_id: current_organization.id)
            .merge(customer: current_customer(args[:customer_id]))
            .except(:customer_id)
        )

        result.success? ? result.wallet : result_error(result)
      end

      def current_customer(id)
        current_organization.customers.find_by(id:)
      end

      private

      # NOTE: The wallet form always sends grantedCredits ("0" when empty), so only an amount that
      #       actually grants credits is privileged.
      def privileged_params?(args)
        non_zero_amount?(args[:granted_credits]) ||
          args[:ignore_paid_top_up_limits_on_creation] == true ||
          args[:recurring_transaction_rules].present?
      end

      def non_zero_amount?(value)
        return false if value.nil?

        BigDecimal(value, exception: false) != 0
      end
    end
  end
end
