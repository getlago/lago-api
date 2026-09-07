# frozen_string_literal: true

module Webhooks
  # Quote, order form and order webhooks are premium and feature flagged. The gate is
  # re-evaluated at delivery time rather than trusted from the enqueue site, as the
  # license or the flag may have changed since.
  module OrderFormsGate
    extend ActiveSupport::Concern
    include ::OrderForms::Premium

    def call
      return unless order_forms_enabled?(current_organization)

      super
    end
  end
end
