# frozen_string_literal: true

module UsageMonitoring
  module CatalogWalletAlertSettings
    extend ActiveSupport::Concern

    ALERT_TYPES = {
      balance: "balance",
      ongoing_balance: "ongoing_balance"
    }.freeze

    included do
      include CatalogCodeFormat

      belongs_to :organization

      enum :alert_type, ALERT_TYPES, validate: true

      validates :code, presence: true
    end

    # ProcessAlertService skips discarded alerts. These alerts are deleted for good, so one that could be loaded
    # is never discarded; one deleted after it was loaded raises RecordNotFound in with_lock, which the evaluation
    # job skips itself.
    def discarded?
      false
    end
  end
end
