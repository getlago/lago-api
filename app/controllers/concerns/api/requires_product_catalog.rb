# frozen_string_literal: true

# Guards new product-catalog (v2) REST endpoints: only organizations with the
# product_catalog premium integration may use them.
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
