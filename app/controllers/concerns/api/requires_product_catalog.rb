# frozen_string_literal: true

# Guards v2 catalog endpoints: requires the organization's product_catalog flag.
module Api
  module RequiresProductCatalog
    extend ActiveSupport::Concern

    included do
      before_action :ensure_product_catalog!
    end

    private

    def ensure_product_catalog!
      forbidden_error(code: "feature_unavailable") unless current_organization&.product_catalog_enabled?
    end
  end
end
