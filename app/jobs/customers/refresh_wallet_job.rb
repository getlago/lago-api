# frozen_string_literal: true

module Customers
  # Deprecated, kept for one release so the jobs enqueued under this name before the rename still
  # deserialize. A refresh requested with `wallet_ids` runs on a customer the sweep does not flag,
  # so one lost here would not be picked up again. Delete once the queue has drained.
  class RefreshWalletJob < RefreshWalletsJob
  end
end
