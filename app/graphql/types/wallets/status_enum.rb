# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Wallets
    class StatusEnum < Types::BaseEnum
      graphql_name "WalletStatusEnum"

      Wallet::STATUSES.each do |type|
        value type
      end
    end
  end
end
