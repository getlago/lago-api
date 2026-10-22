# frozen_string_literal: true

module X402
  module Customers
    class ResolveService < BaseService
      Result = BaseResult[:customer]

      def initialize(organization:, address:, family:)
        @organization = organization
        @address = address
        @family = family

        super
      end

      def call
        external_id = X402::ExternalIds.customer(address, family:)
        result.customer = find_customer || create_customer(external_id)
        result
      rescue BaseService::FailedResult => e
        result.fail_with_error!(e)
      end

      private

      attr_reader :organization, :address, :family

      def find_customer
        organization.customers.by_x402_agent_address(address).first
      end

      def create_customer(external_id)
        ActiveRecord::Base.transaction(requires_new: true) do
          ::Customers::CreateService.call!(
            organization_id: organization.id,
            external_id:,
            x402_agent_address: address,
            finalize_zero_amount_invoice: :skip,
            exclude_from_dunning_campaign: true
          ).customer
        end
      rescue ActiveRecord::RecordNotUnique, BaseService::FailedResult
        find_customer || raise
      end
    end
  end
end
