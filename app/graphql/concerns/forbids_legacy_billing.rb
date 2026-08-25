# frozen_string_literal: true

# Blocks legacy pricing mutations for product-catalog organizations.
module ForbidsLegacyBilling
  def ready?(**args)
    raise forbidden_error(code: "legacy_billing_disabled") if current_organization&.product_catalog_enabled?

    super
  end
end
