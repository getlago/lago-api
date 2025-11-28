# frozen_string_literal: true

module Api
  module V1
    module CreditNotes
      class MetadataController < BaseController
        def create
          result = Metadata::UpdateItemService.call(credit_note, value:, replace: true)

          if result.success?
            render_metadata
          else
            render_error_response(result)
          end
        end

        def update
          result = Metadata::UpdateItemService.call(credit_note, value:)

          if result.success?
            render_metadata
          else
            render_error_response(result)
          end
        end

        def destroy
          result = Metadata::UpdateItemService.call(credit_note, value: nil, replace: true)

          if result.success?
            render_metadata
          else
            render_error_response(result)
          end
        end

        private

        def value
          params.fetch(:metadata, {}).permit!.to_h
        end

        def render_metadata
          render(json: {metadata: credit_note.reload.metadata&.value})
        end
      end
    end
  end
end
