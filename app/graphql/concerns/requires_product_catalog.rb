# frozen_string_literal: true

# Guards catalog mutations/resolvers: requires the product_catalog flag.
module RequiresProductCatalog
  def ready?(**args)
    raise forbidden_error(code: "feature_unavailable") unless current_organization&.product_catalog_enabled?

    super
  end
end
