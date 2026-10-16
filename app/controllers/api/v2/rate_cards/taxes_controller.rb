# frozen_string_literal: true

module Api
  module V2
    module RateCards
      class TaxesController < Api::V2::BaseController
        # Paged on the links of the rate card, which render as their taxes.
        cursor_paginated_index(::RateCard::AppliedTax)

        before_action :find_rate_card

        def index
          result = ::RateCardTaxesQuery.call(
            organization: current_organization,
            pagination: cursor,
            filters: {rate_card_id: rate_card.id}
          )

          if result.success?
            page = ::CursorPagination::Page.new(records: result.applied_taxes, cursor:)

            render(
              json: ::CollectionSerializer.new(
                # A tax discarded between the page query and the preload of its taxes loads as nil.
                page.records.filter_map(&:tax),
                ::V2::TaxSerializer,
                collection_name: "taxes",
                meta: page.meta,
                includes: serializer_includes
              )
            )
          else
            render_error_response(result)
          end
        end

        private

        attr_reader :rate_card

        def find_rate_card
          @rate_card = current_organization.rate_cards.find_by(code: params[:rate_card_code])

          not_found_error(resource: "rate_card") unless rate_card
        end

        def resource_name
          "rate_card"
        end
      end
    end
  end
end
