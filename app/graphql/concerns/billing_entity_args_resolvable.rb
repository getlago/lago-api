# frozen_string_literal: true

module BillingEntityArgsResolvable
  extend ActiveSupport::Concern

  private

  # Replaces the `billing_entity_code` argument with the matching `billing_entity_id`
  # so analytics models only deal with ids.
  # Mutates `args` and returns an execution error when the arguments are invalid, nil otherwise.
  def resolve_billing_entity!(args)
    if args[:billing_entity_code].present? && args[:billing_entity_id].present?
      return validation_error(messages: {billing_entity_id: ["can't be present when billing_entity_code is provided"]})
    end

    code = args.delete(:billing_entity_code)
    return nil if code.blank?

    billing_entity = current_organization.billing_entities.find_by(code:)
    if billing_entity.nil?
      return not_found_error(resource: "billing_entity")
    end

    args[:billing_entity_id] = billing_entity.id
    nil
  end
end
