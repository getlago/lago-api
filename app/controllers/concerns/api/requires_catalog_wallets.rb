# frozen_string_literal: true

module Api
  module RequiresCatalogWallets
    extend ActiveSupport::Concern

    included do
      before_action :ensure_catalog_wallets!
    end

    private

    def ensure_catalog_wallets!
      forbidden_error(code: "feature_unavailable") unless current_organization&.catalog_wallets_enabled?
    end
  end
end
