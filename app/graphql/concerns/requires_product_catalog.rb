# frozen_string_literal: true

# Guards new product-catalog (v2) GraphQL mutations/resolvers: only
# organizations with the product_catalog premium integration may use them.
module RequiresProductCatalog
  def ready?(**args)
    raise forbidden_error(code: "feature_unavailable") unless current_organization&.product_catalog_enabled?

    super
  end
end
