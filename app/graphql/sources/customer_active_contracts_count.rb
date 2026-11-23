# frozen_string_literal: true

module Sources
  # Batches the active contracts count of customers into one grouped query.
  #
  # Usage in GraphQL types:
  #   dataloader.with(Sources::CustomerActiveContractsCount).load(object.id)
  class CustomerActiveContractsCount < GraphQL::Dataloader::Source
    def fetch(customer_ids)
      counts = Contract.active.where(customer_id: customer_ids).reorder(nil).group(:customer_id).count

      customer_ids.map { counts.fetch(it, 0) }
    end
  end
end
