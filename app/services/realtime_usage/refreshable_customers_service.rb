# frozen_string_literal: true

module RealtimeUsage
  # Which of a batch's customers a wallet refresh could act on, and the wallets it would touch.
  class RefreshableCustomersService < BaseService
    Result = BaseResult[:customers, :active_wallet_ids]

    # @param triggers [Hash] one entry per customer, keyed by customer id, each carrying an
    #   `organization_id`
    def initialize(triggers:)
      @triggers = triggers

      super
    end

    def call
      result.customers = customers
      result.active_wallet_ids = active_wallet_ids
      result
    end

    private

    attr_reader :triggers

    # One query for the whole batch. No active wallet, a tax error, or an organization off the
    # rollout each make the refresh a no-op, so none of them is worth dispatching.
    def customers
      @customers ||= Customer
        .with_active_wallets
        .without_tax_errors
        .includes(:organization)
        .where(organization_id: triggers.each_value.map { it[:organization_id] }.uniq, id: triggers.keys)
        .distinct
        .index_by(&:id)
        .select { |_id, customer| RealtimeUsage.enabled?(customer.organization) }
    end

    # One query for the whole batch. The wallet ids let the job run for a customer the sweep has
    # not flagged, so this lane does not ride on the sweep's bookkeeping.
    #
    # Ordered because the job's uniqueness lock digests its arguments: an unstable array order
    # would key the same refresh twice and let two of them run concurrently.
    def active_wallet_ids
      Wallet
        .active
        .where(customer_id: customers.keys)
        .order(:id)
        .pluck(:customer_id, :id)
        .group_by(&:first)
        .transform_values { |pairs| pairs.map(&:last) }
    end
  end
end
