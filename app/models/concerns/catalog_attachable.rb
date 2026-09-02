# frozen_string_literal: true

module CatalogAttachable
  def attached_to_plan_or_subscription?
    plan_applied_rate_cards.exists? || contract_applied_rate_cards.exists?
  end
end
