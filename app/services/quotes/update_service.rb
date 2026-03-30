# frozen_string_literal: true

module Quotes
  class UpdateService < BaseService
    Result = BaseResult[:quote]

    def initialize(quote:, params:)
      @quote = quote
      @params = params

      super
    end

    def call
      return result.not_found_failure!(resource: "quote") unless quote
      return result.not_allowed_failure!(code: "quote_not_draft") unless quote.draft?

      if params.key?(:billing_items) && params[:billing_items].present?
        return result unless Quotes::BillingItemsValidator.new(
          result,
          billing_items: params[:billing_items],
          order_type: quote.order_type
        ).valid?
      end

      quote.currency = params[:currency] if params.key?(:currency)
      quote.description = params[:description] if params.key?(:description)
      quote.content = params[:content] if params.key?(:content)
      quote.legal_text = params[:legal_text] if params.key?(:legal_text)
      quote.internal_notes = params[:internal_notes] if params.key?(:internal_notes)
      quote.billing_items = params[:billing_items] if params.key?(:billing_items)
      quote.commercial_terms = params[:commercial_terms] if params.key?(:commercial_terms)
      quote.contacts = params[:contacts] if params.key?(:contacts)
      quote.metadata = params[:metadata] if params.key?(:metadata)
      quote.auto_execute = params[:auto_execute] if params.key?(:auto_execute)
      quote.execution_mode = params[:execution_mode] if params.key?(:execution_mode)
      quote.backdated_billing = params[:backdated_billing] if params.key?(:backdated_billing)

      ActiveRecord::Base.transaction do
        update_owners if params.key?(:owner_ids)
        quote.save!
      end

      result.quote = quote
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :quote, :params

    def organization
      @quote.organization
    end

    def update_owners
      return unless params[:owner_ids].is_a?(Array)

      existing_ids = quote.quote_owners.pluck(:user_id)
      return if existing_ids.to_set == params[:owner_ids].to_set

      quote.quote_owners.delete_all

      organization.users.where(id: params[:owner_ids]).map do |user|
        quote.quote_owners.build(user:, organization:)
      end
    end
  end
end
