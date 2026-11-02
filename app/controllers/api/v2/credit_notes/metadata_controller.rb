# frozen_string_literal: true

module Api
  module V2
    module CreditNotes
      class MetadataController < Api::V2::BaseController
        before_action :find_credit_note

        def create
          return invalid_metadata_request unless valid_metadata?

          update_metadata(metadata:)
        end

        def update
          return invalid_metadata_request unless valid_metadata?

          update_metadata(partial_metadata: true, metadata:)
        end

        def destroy
          update_metadata(metadata: nil)
        end

        def destroy_key
          return not_found_error(resource: "metadata") unless credit_note.metadata

          result = Metadata::DeleteItemKeyService.call(item: credit_note.metadata, key: params[:key])
          result.success? ? render_metadata : render_error_response(result)
        end

        private

        attr_reader :credit_note

        def find_credit_note
          @credit_note = current_organization.credit_notes.finalized.find_by(id: params[:credit_note_id])
          not_found_error(resource: "credit_note") unless @credit_note
        end

        def update_metadata(**attributes)
          result = ::CreditNotes::UpdateService.call(credit_note:, **attributes)
          result.success? ? render_metadata : render_error_response(result)
        end

        def metadata
          value = metadata_params
          value.is_a?(ActionController::Parameters) ? value.permit!.to_h : value.to_h
        end

        def metadata_params
          params.fetch(:metadata, {})
        end

        def valid_metadata?
          metadata_params.is_a?(ActionController::Parameters) || metadata_params.is_a?(Hash)
        end

        def invalid_metadata_request
          details = {reason: "value_is_invalid"}
          details[:value] = metadata_params if metadata_params.is_a?(String)

          invalid_request_error(
            code: "value_is_invalid",
            error_details: {metadata: details}
          )
        end

        def render_metadata
          render(json: {metadata: credit_note.reload.metadata&.value})
        end

        def resource_name
          "credit_note"
        end
      end
    end
  end
end
