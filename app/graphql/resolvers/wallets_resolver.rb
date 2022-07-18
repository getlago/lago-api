# frozen_string_literal

module Resolvers
  class WalletsResolver < GraphQL::Schema::Resolver
    include AuthenticableApiUser
    include RequiredOrganization

    description 'Query wallets'

    argument :ids, [ID], required: false, description: 'List of wallet IDs to fetch'
    argument :customer_id, required: true
    argument :page, Integer, required: false
    argument :limit, Integer, required: false
    argument :status, Types::Wallets::StatusEnum, required: false

    type Types::Wallets::Object.collection_type, null: false

    def resolve(ids: nil, page: nil, limit: nil, status: nil)
      validate_organization!

      wallets = current_customer
        .wallets
        .page(page)
        .limit(limit)

      wallets = wallets.where(status: status) if status.present?
      wallets = wallets.where(id: ids) if ids.present?

      wallets
    rescue ActiveRecord::RecordNotFound
      not_found_error
    end

    private

    def current_customer
      @current_customer ||= Customer.find(customer_id)
    end
  end
end
