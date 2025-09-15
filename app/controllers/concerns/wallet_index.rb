# frozen_string_literal: true

module WalletIndex
  include Pagination
  extend ActiveSupport::Concern

  def wallet_index(external_customer_id:)
    result = WalletsQuery.call(
      organization: current_organization,
      pagination: {
        page: params[:page],
        limit: params[:per_page] || PER_PAGE
      },
      filters: {external_customer_id: external_customer_id}
    )

    if result.success?
      render(
        json: ::CollectionSerializer.new(
          result.wallets.includes(:recurring_transaction_rules),
          ::V1::WalletSerializer,
          collection_name: "wallets",
          meta: pagination_metadata(result.wallets),
          includes: %i[recurring_transaction_rules limitations]
        )
      )
    else
      render_error_response(result)
    end
  end
end
