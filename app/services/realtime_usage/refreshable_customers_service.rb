# frozen_string_literal: true

module RealtimeUsage
  # Which of a batch's customers a wallet refresh could act on.
  class RefreshableCustomersService < BaseService
    Result = BaseResult[:customers]

    # @param triggers [Hash] one entry per customer, keyed by customer id, each carrying an
    #   `organization_id`
    def initialize(triggers:)
      @triggers = triggers

      super
    end

    def call
      result.customers = customers
      result
    end

    private

    attr_reader :triggers

    # One query for the whole batch. No active wallet, a tax error, or an organization off the
    # rollout each make the refresh a no-op, so none of them is worth dispatching.
    def customers
      Customer
        .with_active_wallets
        .without_tax_errors
        .includes(:organization)
        .where(organization_id: triggers.each_value.map { it[:organization_id] }.uniq, id: triggers.keys)
        .distinct
        .index_by(&:id)
        .select { |_id, customer| RealtimeUsage.enabled?(customer.organization) }
    end
  end
end
