# frozen_string_literal: true

module Quotes
  class UpdateService < BaseService
    attr_reader :quote, :params

    def initialize(quote:, params:)
      @quote = quote
      @params = params
      super
    end

    def call
      return result.forbidden_failure! unless License.premium?
      return result.not_found_failure!(resource: "quote") unless quote
      return result.validation_failure!(errors: {quote: ["inappropriate_state"]}) unless editable?

      update_params = params.slice(
        :auto_execute,
        :backdated_billing,
        :billing_items,
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
      Quote.transaction do
        quote.update!(update_params)
        sync_owners!(quote:, owners: params[:owners]) if params.has_key?(:owners)
      end

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
