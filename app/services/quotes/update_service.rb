# frozen_string_literal: true

module Quotes
  class UpdateService < BaseService
    attr_reader :quote, :params

    Result = BaseResult[:quote]

    def initialize(quote:, params:)
      @quote = quote
      @params = params
      super
    end

    def call
      return result.forbidden_failure! unless License.premium?
      return result.not_found_failure!(resource: "quote") unless quote
      return result.forbidden_failure! unless quote.organization.feature_flag_enabled?(:order_forms)
      return result.not_allowed_failure!(code: "inappropriate_state") unless editable?

      update_params = params.slice(
        :auto_execute,
        :backdated_billing,
        :commercial_terms,
        :contacts,
        :content,
        :currency,
        :description,
        :execution_mode,
        :internal_notes,
        :legal_text,
        :metadata,
        :order_type
      )

      if params.key?(:billing_items)
        validation = Quotes::BillingItems::ValidateService.call(
          organization: quote.organization,
          order_type: quote.order_type,
          billing_items: params[:billing_items]
        )
        return validation unless validation.success?

        update_params[:billing_items] = validation.billing_items
      end

      Quote.transaction do
        quote.update!(update_params)
        sync_owners!(quote:, owners: params[:owners]) if params.has_key?(:owners)
      end

      # TODO: SendWebhookJob.perform_after_commit("quote.updated", quote)

      result.quote = quote.reload
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    def editable?
      quote.draft?
    end

    def sync_owners!(quote:, owners:)
      new_owners = owners.uniq
      current_owners = quote.owner_ids

      owners_to_remove = current_owners - new_owners
      quote.quote_owners.where(user_id: owners_to_remove).delete_all if owners_to_remove.any?

      owners_to_add = new_owners - current_owners
      owners_to_add.each do |user_id|
        quote.quote_owners.create!(
          organization_id: quote.organization_id,
          user_id: user_id
        )
      end
    end
  end
end
