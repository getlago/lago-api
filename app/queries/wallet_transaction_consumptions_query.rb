# frozen_string_literal: true

class WalletTransactionConsumptionsQuery < BaseQuery
  Result = BaseResult[:wallet_transaction_consumptions]

  DIRECTIONS = %i[consumptions fundings].freeze

  def initialize(organization:, wallet_transaction_id:, direction:, pagination: DEFAULT_PAGINATION_PARAMS)
    @wallet_transaction = organization.wallet_transactions.find_by(id: wallet_transaction_id)
    @direction = direction.to_sym

    raise ArgumentError, "Invalid direction: #{@direction}" unless DIRECTIONS.include?(@direction)

    super(organization:, pagination:)
  end

  def call
    return result.not_found_failure!(resource: "wallet_transaction") unless wallet_transaction
    return result.single_validation_failure!(field: :wallet, error_code: "not_traceable") unless wallet_transaction.wallet.traceable?
    return result.single_validation_failure!(field: :transaction_type, error_code: "invalid_transaction_type") unless valid_transaction_type?

    consumptions = wallet_transaction.public_send(direction)
    consumptions = paginate(consumptions)
    consumptions = apply_consistent_ordering(consumptions)

    result.wallet_transaction_consumptions = consumptions
    result
  end

  private

  attr_reader :wallet_transaction, :direction

  def valid_transaction_type?
    case direction
    when :consumptions
      wallet_transaction.inbound?
    when :fundings
      wallet_transaction.outbound?
    end
  end
end
