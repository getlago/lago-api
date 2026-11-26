# frozen_string_literal: true

module Api
  module CatalogWalletParams
    include UnfilteredParams

    UNFILTERED_PARAMS = %i[tax_codes applies_to metadata].freeze

    private

    def catalog_wallet_params(root)
      wallet = params.require(root)
      raise ActionController::ParameterMissing, root unless wallet.is_a?(ActionController::Parameters)

      permitted = wallet.permit(
        :code,
        :name,
        :invoice_display_name,
        :currency,
        :tax_application,
        :priority,
        :top_up_min_amount_cents,
        :top_up_max_amount_cents,
        tax_codes: [],
        applies_to: {},
        metadata: {}
      ).to_h

      # Strong params drop a null and a value of another shape. The services need both: a null
      # metadata clears it, and another shape is refused instead of ignored.
      UNFILTERED_PARAMS.each do |key|
        permitted[key] = unfiltered(wallet[key]) if wallet.key?(key) && !permitted.key?(key)
      end

      permitted
    end
  end
end
