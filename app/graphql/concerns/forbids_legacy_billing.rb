# frozen_string_literal: true

# Blocks legacy pricing GraphQL mutations once an organization is on the
# product catalog.
module ForbidsLegacyBilling
  def ready?(**args)
    raise forbidden_error(code: "legacy_billing_disabled") if current_organization&.product_catalog_enabled?

    super
  end
end
